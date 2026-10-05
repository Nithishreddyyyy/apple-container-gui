#!/usr/bin/env python3
"""Launch the container GUI with friendly diagnostics.

Usage:
    python3 Usage.py            # check prerequisites and launch the GUI
    python3 Usage.py --check    # diagnostics only, do not launch
    python3 Usage.py --help     # this message

Works with the system Python on macOS (Tk 8.5 via /usr/bin/python3) or any
Python with Tkinter. stdlib only — no pip dependencies.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys

GUI_DIR = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.join(GUI_DIR, "src")
sys.path.insert(0, GUI_DIR)


def check_python() -> tuple[bool, str]:
    v = sys.version_info
    line = f"Python {v.major}.{v.minor}.{v.micro} ({sys.executable})"
    ok = v >= (3, 8)
    return ok, line + (" — OK" if ok else " — needs Python 3.8+")


def check_tkinter() -> tuple[bool, str]:
    try:
        import tkinter  # noqa: F401
        from tkinter import TkVersion
        return True, f"Tkinter available (Tk {TkVersion}) — OK"
    except Exception as e:
        return False, (
            "Tkinter NOT available: " + str(e) + "\n"
            "  macOS fix: run with the system Python:\n"
            "      /usr/bin/python3 Usage.py\n"
            "  (Homebrew Python often lacks _tkinter; "
            "install python-tk or use python.org builds.)"
        )


def check_container() -> tuple[bool, str]:
    explicit = os.environ.get("CONTAINER_CLI")
    path = shutil.which(explicit) if explicit and "/" not in explicit else explicit
    if not path:
        path = shutil.which("container")
    if not path:
        return False, (
            "`container` NOT found on PATH.\n"
            "  Install from https://github.com/apple/container/releases, then:\n"
            "      container system start"
        )
    try:
        cp = subprocess.run([path, "system", "version"],
                            capture_output=True, text=True, timeout=20)
        ver = (cp.stdout.strip().splitlines() or [""])[0][:120]
        detail = f" (`{ver}`)" if ver else ""
        return True, f"`container` found at {path}{detail} — OK"
    except Exception as e:
        return True, f"`container` found at {path} (version check: {e}) — OK"


def check_system_service(container_path: str | None) -> str:
    if not container_path:
        return "System service: unknown (`container` missing)"
    try:
        cp = subprocess.run([container_path, "system", "status", "--format", "json"],
                            capture_output=True, text=True, timeout=20)
        out = (cp.stdout or "").strip()[:200]
        if '"running"' in out or "'running'" in out or "running" in out.lower():
            state = "running"
        else:
            state = out or (cp.stderr.strip()[:200] or "not running")
        return f"System service probe: {state}"
    except Exception as e:
        return f"System service probe failed: {e}"


def main(argv: list[str]) -> int:
    check_only = "--check" in argv
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0

    print("=== Container GUI prerequisites ===")
    ok_py, msg_py = check_python()
    print(f"[{'OK' if ok_py else '!!'}] {msg_py}")
    ok_tk, msg_tk = check_tkinter()
    print(f"[{'OK' if ok_tk else '!!'}] {msg_tk}")
    ok_cli, msg_cli = check_container()
    print(f"[{'OK' if ok_cli else '!!'}] {msg_cli}")
    cpath = shutil.which("container")
    print(f"[..] {check_system_service(cpath)}")
    print()
    print(f"Tip: Apple Silicon + macOS 26 recommended. GUI dir: {GUI_DIR}")

    if not (ok_py and ok_tk and ok_cli):
        print()
        print("Missing prerequisites — GUI not launched. Fix the items "
              "marked [!!] above and retry.")
        if not ok_tk and shutil.which("/usr/bin/python3"):
            print("Hint: try  /usr/bin/python3 Usage.py")
        return 1

    if check_only:
        print()
        print("All checks passed (check-only mode, GUI not launched).")
        return 0

    print()
    print("Launching Container Manager…")
    try:
        from src.app import main as app_main
        from src.cli import ContainerService
        app_main(ContainerService())
    except Exception as e:
        # If the failure is just "no display", explain instead of tracebacks.
        if "display" in str(e).lower() or "$DISPLAY" in str(e):
            print(f"Could not open a window: {e}")
            print("This GUI needs a macOS graphical session (not plain SSH).")
            return 1
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
