"""Safe subprocess adapter over the `container` CLI.

Security model (see GUI/logs/architecture.md):
  * Never ``shell=True``. Always argv arrays.
  * Binary resolved via ``shutil.which`` (or ``CONTAINER_CLI`` override) and
    executed by absolute path.
  * User-controlled identifiers (container IDs, image refs) are validated
    against a strict allowlist before ever reaching subprocess.
  * Timeouts + output caps on every call; UTF-8 with replacement.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from typing import List, Optional, Sequence

from .models import ContainerInfo, ImageInfo, SystemStatus

DEFAULT_TIMEOUT = 30
MAX_OUTPUT_BYTES = 512 * 1024

# Container IDs/names, image references: letters, digits and the punctuation
# used by OCI references. Anything else (spaces, shell metachars, quotes,
# backslashes, semicolons, dollar, backtick, pipe, redirects...) is rejected.
_ID_RE = re.compile(r"^[A-Za-z0-9_.\-/:@]+$")
_MAX_ID_LEN = 256


class ContainerCLIError(RuntimeError):
    """A `container` CLI invocation failed."""


@dataclass
class CLIResult:
    returncode: int
    stdout: str
    stderr: str
    argv: List[str]

    @property
    def ok(self) -> bool:
        return self.returncode == 0


def find_container_binary(explicit: Optional[str] = None) -> Optional[str]:
    """Resolve the `container` binary path, or None if not installed."""
    candidates = []
    env_override = os.environ.get("CONTAINER_CLI")
    if explicit:
        candidates.append(explicit)
    if env_override:
        candidates.append(env_override)
    candidates.append("container")
    for c in candidates:
        p = shutil.which(c) if "/" not in c else (c if os.path.isfile(c) else None)
        if p and os.access(p, os.X_OK):
            return p
    return None


def validate_identifier(value: str, kind: str = "identifier") -> str:
    """Validate a user-controlled CLI argument. Raises ValueError."""
    v = (value or "").strip()
    if not v:
        raise ValueError(f"{kind} must not be empty")
    if len(v) > _MAX_ID_LEN:
        raise ValueError(f"{kind} is too long (max {_MAX_ID_LEN} chars)")
    if not _ID_RE.match(v):
        raise ValueError(
            f"Invalid {kind} {v!r}: only letters, digits and "
            "`_ . - / : @` are allowed"
        )
    return v


def validate_image_ref(value: str) -> str:
    return validate_identifier(value, kind="image reference")


def _daemon_down_hint(stderr: str) -> bool:
    markers = (
        "Ensure container system service has been started",
        "Connection invalid",
        "failed to list containers",
        "apiserver",
        "not running",
        "unregistered",
    )
    low = (stderr or "").lower()
    return any(m.lower() in low for m in markers)


class ContainerService:
    """High-level GUI-facing facade over the CLI."""

    def __init__(self, binary: Optional[str] = None,
                 timeout: int = DEFAULT_TIMEOUT):
        resolved = find_container_binary(binary)
        if resolved is None:
            raise ContainerCLIError(
                "The `container` command was not found on PATH. "
                "Install it from https://github.com/apple/container/releases "
                "and run `container system start`."
            )
        self.binary = resolved
        self.timeout = timeout

    # -- low-level -----------------------------------------------------
    def run_raw(self, args: Sequence[str],
                timeout: Optional[int] = None) -> CLIResult:
        argv = [self.binary, *[str(a) for a in args]]
        try:
            cp = subprocess.run(
                argv,
                capture_output=True,
                text=True,
                errors="replace",
                timeout=self.timeout if timeout is None else timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as e:
            raise ContainerCLIError(
                f"Timed out running `{' '.join(argv)}` "
                f"after {self.timeout}s"
            ) from e
        except OSError as e:
            raise ContainerCLIError(f"Failed to launch `{' '.join(argv)}`: {e}") from e
        stdout = (cp.stdout or "")[:MAX_OUTPUT_BYTES]
        stderr = (cp.stderr or "")[:MAX_OUTPUT_BYTES]
        return CLIResult(cp.returncode or 0, stdout, stderr, argv)

    def _ensure_ok(self, res: CLIResult) -> CLIResult:
        if res.ok:
            return res
        msg = (res.stderr.strip() or res.stdout.strip()
               or f"exited with code {res.returncode}")
        if _daemon_down_hint(res.stderr + res.stdout):
            msg += ("\n\nHint: the container system service looks stopped. "
                    "Run `container system start` (System tab) and retry.")
        raise ContainerCLIError(msg)

    @staticmethod
    def _parse_json_array(stdout: str) -> list:
        text = (stdout or "").strip()
        if not text:
            return []
        try:
            data = json.loads(text)
        except json.JSONDecodeError as e:
            raise ContainerCLIError(f"Could not parse CLI JSON output: {e}")
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            # Some commands wrap arrays (e.g. TOML compat); accept `items`.
            for key in ("items", "containers", "images"):
                if isinstance(data.get(key), list):
                    return data[key]
            return [data]
        raise ContainerCLIError("Unexpected JSON shape from CLI")

    @staticmethod
    def _parse_json_object(stdout: str) -> dict:
        text = (stdout or "").strip()
        if not text:
            return {}
        try:
            data = json.loads(text)
        except json.JSONDecodeError as e:
            raise ContainerCLIError(f"Could not parse CLI JSON output: {e}")
        if isinstance(data, dict):
            return data
        if isinstance(data, list) and data and isinstance(data[0], dict):
            return data[0]
        raise ContainerCLIError("Unexpected JSON shape from CLI")

    # -- containers ----------------------------------------------------
    def list_containers(self) -> List[ContainerInfo]:
        res = self._ensure_ok(
            self.run_raw(["list", "--all", "--format", "json"]))
        return [ContainerInfo.from_dict(d) for d in self._parse_json_array(res.stdout)
                if isinstance(d, dict)]

    def start_container(self, container_id: str) -> CLIResult:
        cid = validate_identifier(container_id, "container id")
        return self._ensure_ok(self.run_raw(["start", cid]))

    def stop_container(self, container_id: str,
                       timeout_secs: int = 5) -> CLIResult:
        cid = validate_identifier(container_id, "container id")
        return self._ensure_ok(
            self.run_raw(["stop", "--time", str(int(timeout_secs)), cid],
                         timeout=max(self.timeout, int(timeout_secs) + 15)))

    def restart_container(self, container_id: str) -> CLIResult:
        # No dedicated `restart` subcommand; stop then start for a genuine restart.
        cid = validate_identifier(container_id, "container id")
        self._ensure_ok(self.run_raw(["stop", cid]))
        return self._ensure_ok(self.run_raw(["start", cid]))

    def remove_container(self, container_id: str,
                         force: bool = False) -> CLIResult:
        cid = validate_identifier(container_id, "container id")
        args = ["rm"]
        if force:
            args.append("--force")
        args.append(cid)
        # `rm` is an alias of `delete`; fall back if alias missing.
        res = self.run_raw(args)
        if not res.ok and "unknown command" in (res.stderr or "").lower():
            args2 = ["delete"] + (["--force"] if force else []) + [cid]
            res = self.run_raw(args2)
        return self._ensure_ok(res)

    def container_logs(self, container_id: str,
                       tail: int = 200) -> CLIResult:
        cid = validate_identifier(container_id, "container id")
        return self._ensure_ok(
            self.run_raw(["logs", "--number", str(int(tail)), cid]))

    def inspect_container(self, container_id: str) -> str:
        cid = validate_identifier(container_id, "container id")
        res = self._ensure_ok(self.run_raw(["inspect", cid]))
        return res.stdout

    def run_container(self, image: str, name: str = "",
                      extra_args: Optional[Sequence[str]] = None) -> CLIResult:
        ref = validate_image_ref(image)
        args = ["run", "--detach"]
        if name.strip():
            args += ["--name", validate_identifier(name.strip(), "container name")]
        # Extra args are intentionally NOT free-form: only allow a tiny set of
        # known-safe flags to avoid injection via the GUI.
        if extra_args:
            raise ContainerCLIError("Extra run flags are not supported by the GUI")
        args.append(ref)
        return self._ensure_ok(self.run_raw(args, timeout=120))

    # -- images --------------------------------------------------------
    def list_images(self) -> List[ImageInfo]:
        res = self._ensure_ok(
            self.run_raw(["image", "list", "--format", "json"]))
        return [ImageInfo.from_dict(d) for d in self._parse_json_array(res.stdout)
                if isinstance(d, dict)]

    def pull_image(self, ref: str) -> CLIResult:
        r = validate_image_ref(ref)
        return self._ensure_ok(
            self.run_raw(["image", "pull", "--progress", "plain", r],
                         timeout=600))

    def remove_image(self, ref: str, force: bool = False) -> CLIResult:
        r = validate_image_ref(ref)
        args = ["image", "rm"] + (["--force"] if force else []) + [r]
        return self._ensure_ok(self.run_raw(args, timeout=120))

    # -- system --------------------------------------------------------
    def system_status(self) -> SystemStatus:
        res = self.run_raw(["system", "status", "--format", "json"])
        # status exits non-zero when down; still parse the JSON payload.
        try:
            obj = self._parse_json_object(res.stdout)
        except ContainerCLIError:
            if res.ok:
                raise
            raise ContainerCLIError(
                (res.stderr.strip() or "container system is not running")
                + "\n\nHint: run `container system start` (System tab) and retry."
            )
        return SystemStatus.from_dict(obj)

    def system_start(self) -> CLIResult:
        return self._ensure_ok(self.run_raw(["system", "start"], timeout=180))

    def system_stop(self) -> CLIResult:
        return self._ensure_ok(self.run_raw(["system", "stop"], timeout=120))

    def system_version(self) -> str:
        res = self._ensure_ok(
            self.run_raw(["system", "version", "--format", "json"]))
        return res.stdout
