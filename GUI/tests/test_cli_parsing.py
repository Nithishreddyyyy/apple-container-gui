"""Unit tests for the container GUI (no live daemon required).

Run:
    python3 -m unittest discover -s GUI/tests -v
    # or
    python3 GUI/tests/test_cli_parsing.py
"""

import json
import os
import sys
import unittest

GUI_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, GUI_DIR)

from src.cli import (ContainerService, _daemon_down_hint, validate_identifier,
                     validate_image_ref)
from src.models import ContainerInfo, ImageInfo, SystemStatus


class TestValidation(unittest.TestCase):
    def test_valid_ids(self):
        for v in ["web", "my-container_1", "alpine:latest",
                  "registry.io/lib/img@sha256:abc", "a/b/c"]:
            self.assertEqual(validate_identifier(v), v)

    def test_rejects_shell_metachars(self):
        for v in ["a;rm -rf /", "$(evil)", "`evil`", "a|b", "a&b",
                  "a b", "a'b", 'a"b', "a\\b", "a>b", "$HOME", ""]:
            with self.assertRaises(ValueError, msg=v):
                validate_identifier(v)

    def test_rejects_too_long(self):
        with self.assertRaises(ValueError):
            validate_identifier("x" * 300)

    def test_image_ref(self):
        self.assertEqual(validate_image_ref("alpine:latest"), "alpine:latest")
        with self.assertRaises(ValueError):
            validate_image_ref("alpine; echo hi")


class TestModels(unittest.TestCase):
    def test_container_from_dict(self):
        c = ContainerInfo.from_dict({
            "id": "abc123", "name": "web", "image": "nginx:latest",
            "state": "running", "ip": "192.168.1.2",
            "os": "linux", "arch": "arm64",
        })
        self.assertEqual(c.display_name, "web")
        self.assertTrue(c.is_running)
        c2 = ContainerInfo.from_dict({"ID": "x", "Status": "Stopped"})
        self.assertFalse(c2.is_running)

    def test_image_from_dict(self):
        im = ImageInfo.from_dict({"name": "alpine", "tag": "latest",
                                  "os": "linux", "arch": "arm64"})
        self.assertEqual(im.reference, "alpine:latest")

    def test_system_status(self):
        self.assertTrue(SystemStatus.from_dict({"status": "running"}).is_running)
        self.assertFalse(SystemStatus.from_dict({"status": "unregistered"}).is_running)


class TestParsing(unittest.TestCase):
    def test_parse_json_array(self):
        arr = ContainerService._parse_json_array('[{"id": "a"}]')
        self.assertEqual(arr, [{"id": "a"}])
        self.assertEqual(ContainerService._parse_json_array(""), [])
        with self.assertRaises(Exception):
            ContainerService._parse_json_array("not json{")

    def test_parse_json_object(self):
        obj = ContainerService._parse_json_object('{"status": "running"}')
        self.assertEqual(obj["status"], "running")

    def test_daemon_hint(self):
        self.assertTrue(_daemon_down_hint(
            'Error: failed to list containers. Ensure container system '
            'service has been started'))
        self.assertFalse(_daemon_down_hint("some other error"))


class TestLiveProbe(unittest.TestCase):
    """Live CLI probe — passes whether the daemon is up or down.

    Records real behaviour without requiring a running system service.
    Fails only if the `container` binary itself is missing/unusable.
    """

    def test_binary_present_and_help_works(self):
        from src.cli import find_container_binary
        binary = find_container_binary()
        self.assertIsNotNone(binary, "`container` binary not found on PATH")
        import subprocess
        cp = subprocess.run([binary, "--help"], capture_output=True,
                            text=True, timeout=20)
        self.assertEqual(cp.returncode, 0)
        self.assertIn("container", (cp.stdout + cp.stderr).lower())

    def test_system_status_probe(self):
        from src.cli import find_container_binary
        binary = find_container_binary()
        if binary is None:
            self.skipTest("no container binary")
        svc = ContainerService(binary)
        try:
            st = svc.system_status()
            self.assertIn(st.status.lower(),
                          ("running", "not running", "unregistered", "unknown"))
        except Exception as e:
            # Daemon down must raise a *helpful* error, not crash.
            self.assertIn("system", str(e).lower())


class TestRealSchema(unittest.TestCase):
    """Regression tests using the REAL CLI JSON shapes (container 1.2.1).

    Fixtures captured from a live daemon:
      `container list --all --format json`
      `container image list --format json`
    Top-level objects nest data under `configuration` / `status` /
    `variants` — flat-key parsing yields blank rows.
    """

    REAL_CONTAINER = {
        "configuration": {
            "creationDate": "2026-10-05T05:57:33Z",
            "id": "6b60e808-f78f-4fc1-8703-87df0b4f9381",
            "image": {"reference": "docker.io/library/ubuntu:latest"},
            "platform": {"architecture": "arm64", "os": "linux"},
        },
        "id": "6b60e808-f78f-4fc1-8703-87df0b4f9381",
        "status": {"networks": [], "state": "stopped"},
    }

    REAL_CONTAINER_RUNNING = {
        "configuration": {
            "creationDate": "2026-10-05T05:57:33Z",
            "id": "6b60e808-f78f-4fc1-8703-87df0b4f9381",
            "image": {"reference": "docker.io/library/ubuntu:latest"},
            "platform": {"architecture": "arm64", "os": "linux"},
        },
        "id": "6b60e808-f78f-4fc1-8703-87df0b4f9381",
        "status": {"networks": [{"address": "192.168.64.2"}],
                   "state": "running"},
    }

    REAL_IMAGE = {
        "configuration": {"name": "docker.io/library/ubuntu:latest"},
        "id": "f144425ff09be612d6d9ad965196e9cdc23dae1f42110a8a11a3e9a8198759f7",
        "variants": [{"digest": "sha256:3ad1c71aa6b7e477f7aa91445a5442fbb163",
                      "platform": {"architecture": "arm64", "os": "linux"},
                      "size": 40871017}],
    }

    def test_real_container_parses(self):
        c = ContainerInfo.from_dict(self.REAL_CONTAINER)
        self.assertEqual(c.id, "6b60e808-f78f-4fc1-8703-87df0b4f9381")
        self.assertEqual(c.image, "docker.io/library/ubuntu:latest")
        self.assertEqual(c.state, "stopped")
        self.assertEqual(c.os, "linux")
        self.assertEqual(c.arch, "arm64")
        self.assertFalse(c.is_running)

    def test_real_running_container_parses(self):
        c = ContainerInfo.from_dict(self.REAL_CONTAINER_RUNNING)
        self.assertTrue(c.is_running)
        self.assertEqual(c.state, "running")
        self.assertIn("192.168.64.2", c.ip)

    def test_real_image_parses(self):
        im = ImageInfo.from_dict(self.REAL_IMAGE)
        self.assertEqual(im.name, "docker.io/library/ubuntu")
        self.assertEqual(im.tag, "latest")
        self.assertEqual(im.os, "linux")
        self.assertEqual(im.arch, "arm64")
        self.assertTrue(im.size and im.size != "0")
        self.assertTrue(im.digest.startswith("sha256:"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
