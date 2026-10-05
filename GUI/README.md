# Container Manager — GUI for Apple's `container` CLI

A lightweight graphical frontend for common [`apple/container`](https://github.com/apple/container)
workflows: list/inspect containers, start/stop/restart/remove, list/pull/remove
images, check/start/stop the system service, and inspect command output.

This directory (`GUI/`) contains the **entire contribution**, isolated so it
is easy to review, demo, and submit upstream.

## Motivation

`container` is powerful but primarily CLI-oriented. Developers coming from
Docker Desktop expect a small dashboard for day-to-day tasks: *what is
running? start/stop it, pull an image, check the system service, see what
failed*. This contribution provides exactly that — a frontend layer over the
existing CLI. It reimplements nothing; every action shells out to the real
`container` binary.

## Features

- **Dashboard** — container name/ID, image, status (●/○), IP, OS/arch; empty
  state when none exist; refresh.
- **Container actions** — Start, Stop, Restart (stop+start), Remove (with
  confirmation), Logs (tail 200), Inspect (pretty JSON) — all shown in the
  Command Output pane.
- **Images** — list (name/tag/OS/arch/size), Pull… dialog, Remove… (with
  confirmation).
- **System** — `system status` (JSON), Start/Stop with confirmation,
  `system version` display.
- **Logs / errors** — every CLI invocation is echoed as
  `$ container …` with stdout/stderr; failures pop a dialog *and* stay in
  the pane. Daemon-down errors add a
  "run `container system start`" hint.
- **Safety** — argv-array subprocess only (no `shell=True`, no `os.system`);
  identifier allowlist; timeouts; output caps; worker-thread execution so
  the UI never freezes.

## Architecture

```text
┌────────────────────────┐
│       GUI (Tkinter)    │
│  src/app.py (views)    │
└──────────┬─────────────┘
           │ calls
           ▼
┌────────────────────────┐
│ ContainerService       │
│ src/cli.py (adapter)   │
│ models.py (view-model) │
└──────────┬─────────────┘
           │ subprocess argv, --format json
           ▼
┌────────────────────────┐
│ Apple `container` CLI  │
└──────────┬─────────────┘
           │ XPC -> apiserver
           ▼
┌────────────────────────┐
│ Container runtime      │
└────────────────────────┘
```

- `src/models.py` — `ContainerInfo`, `ImageInfo`, `SystemStatus` (tolerant
  JSON wrappers).
- `src/cli.py` — `ContainerService`: binary discovery, validation, `run_raw`,
  per-action methods. The **only** module that touches subprocess.
- `src/app.py` — Tkinter/ttk `App`: three tabs + output pane, worker-thread
  job queue, dialogs.
- `Usage.py` — prerequisite checks + launcher.
- `tests/test_cli_parsing.py` — stdlib `unittest`: validation, model
  mapping, JSON parsing, live binary probe (passes with daemon up or down).

See `logs/architecture.md` for the Tkinter-vs-SwiftUI decision record.

## Requirements

- Mac with Apple silicon (to *run* containers; the GUI itself launches
  anywhere with Tk).
- macOS 26 recommended (per upstream README).
- Python 3.8+ with Tkinter. macOS system Python works:
  `/usr/bin/python3` (Tk 8.5). No pip packages needed (stdlib only).
- `container` installed, e.g. from
  https://github.com/apple/container/releases, on `PATH`
  (or set `CONTAINER_CLI=/path/to/container`).

Note: Homebrew Python on some machines lacks `_tkinter`; if
`python3 Usage.py` complains, retry with `/usr/bin/python3 Usage.py`.

## Running

```bash
cd GUI
python3 Usage.py          # checks + launches
python3 Usage.py --check  # diagnostics only
```

If the system service is stopped, the GUI shows `System: unregistered` /
errors with a hint — open the **System** tab and press **Start System**
(or run `container system start` in a terminal).

## Screenshots

Screenshots live in `screenshots/` when captured on a Mac with a display.
(CI/SSH sessions have no window server, so none are bundled with this
prototype commit — see `logs/testing.md`.)

## Testing

```bash
python3 -m unittest discover -s GUI/tests -v
```

Covers: input validation (incl. shell-metachar rejection), model mapping,
JSON parsing, daemon-hint detection, and a live probe (`--help` +
`system status`) that passes whether the daemon is up or down. Manual GUI
flows are recorded in `logs/testing.md`.

## Limitations

- Tkinter Aqua (Tk 8.5 on system Python) looks dated vs native SwiftUI; no
  Dark-Mode polish, menu-bar/dock integration, or notarized packaging.
- No streaming views (`logs --follow`, `stats` streaming, interactive
  `exec`/TTY, `run` with ports/volumes) — actions are request/response only.
- JSON key names are parsed tolerantly but pinned to CLI 1.x output; a
  future CLI schema change needs adapter updates.
- `restart` = `stop` + `start` (no native restart subcommand).
- Long pulls/starts block a single worker slot (one operation at a time).

## Future improvements

- Native SwiftUI client over `ContainerClient`/XPC (typed errors, progress,
  streaming logs/stats, proper signing) — see `logs/architecture.md`.
- Image pull progress streaming, container stats tab, create/run with
  options, volume/network tabs.
- Bundled `.app` packaging, Dark Mode, accessibility audit.
- `--check` JSON output for scripting.

## Contribution context

Designed as an *additive frontend layer*: zero changes to existing Swift
sources, zero new dependencies for the main project. The only contract with
upstream is the stable CLI surface (`list/image list/system status/...`
with `--format json`). See `logs/pr-description.md` for the proposed PR text.
