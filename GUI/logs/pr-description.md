## Summary

Adds an isolated, lightweight Tkinter GUI (`GUI/`) — a genuine graphical
frontend for Apple's `container` CLI. Dashboard for containers, lifecycle
actions (start/stop/restart/remove/logs/inspect), image list/pull/remove,
system status/start/stop, and a command-output pane. Zero changes to existing
Swift sources; communicates exclusively through the supported CLI surface
(preferring `--format json`) via safe argv-array subprocess.

## Motivation

`container` is powerful but CLI-only. Developers expect a small dashboard for
daily workflows (what's running? start/stop it, pull an image, is the system
service up, what just failed?). This contributes exactly that as an additive
frontend layer — no reimplemented runtime logic. Related closed issues (#1925
open API for GUIs, #348 App Sandbox GUI) confirm community interest; no GUI
code or open GUI PRs exist in-repo, so there is no duplication.

## What Changed

All new files under `GUI/` (nothing else touched):

- `GUI/Usage.py` — prerequisite checks (Python/Tkinter/`container`/service
  probe) + one-command launcher (`python3 Usage.py`).
- `GUI/src/models.py` — `ContainerInfo`, `ImageInfo`, `SystemStatus`
  tolerant JSON view-models.
- `GUI/src/cli.py` — `ContainerService`: binary discovery, allowlist input
  validation, argv-array subprocess (never `shell=True`), timeouts/output
  caps, daemon-down hints; methods for list/start/stop/restart/rm/logs/
  inspect/run/images/pull/system status/start/stop/version.
- `GUI/src/app.py` — Tkinter/ttk app: Containers/Images/System tabs +
  Command Output pane, worker-thread execution, confirmations, empty/
  loading/error states.
- `GUI/tests/test_cli_parsing.py` — 12 stdlib unittests (validation,
  models, parsing, live binary probe).
- `GUI/README.md`, `GUI/logs/{development,architecture,testing}.md`,
  `GUI/requirements.txt` (stdlib-only note).

## Architecture

```text
GUI (Tkinter src/app.py) → ContainerService (src/cli.py) →
`container` CLI (--format json) → runtime (unchanged XPC/apiserver)
```

Tkinter was tried first per contribution guidance and **accepted for this
MVP**: the CLI JSON surface covers the whole scope, the `Usage.py` contract
implies Python, and SwiftUI would break isolation/scope. Direct XPC from
Python was ruled out (Swift-only private Mach service). See
`GUI/logs/architecture.md` for the full decision record, threading model,
and security analysis (argv arrays, allowlists, timeouts, confirmations).

## Testing

- `python3 -m unittest discover -s GUI/tests -v` → **12/12 pass** (also on
  system Python 3.9).
- `Usage.py --check` verified on both interpreters (correctly refuses to
  launch on Homebrew Python lacking `_tkinter`, passes on system Python).
- Real daemon-down CLI output (`unregistered` service) verified: GUI shows
  `System: unregistered` + hint errors instead of crashing.
- Live start/stop of a real container was NOT click-tested here (daemon is
  down; VM boot out of scope) — recorded honestly in `GUI/logs/testing.md`
  with exact demo steps.
- No existing tests affected: zero tracked files modified (`git status`
  shows only `GUI/`).

## Screenshots

Captured on a graphical Mac via `cd GUI && /usr/bin/python3 Usage.py`
(`screenshots/`). Not bundled from headless CI.

## Limitations

Tk 8.5 Aqua looks dated (weak Dark Mode/a11y, no notarized packaging);
no streaming views (`logs -f`, stats streaming, exec TTY); `restart` =
stop+start; single operation at a time; JSON parsing pinned to CLI 1.x keys
(tolerantly).

## Future Work

Native SwiftUI client over `ContainerClient`/XPC; pull progress + stats tab;
run-with-options; volume/network tabs; `.app` bundling and a11y audit.
