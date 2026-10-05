# Development log — container GUI contribution

Agents used (multi-agent approach): Repository Research, Architecture
Research, GUI History Research (parallel subagents), then GUI
Implementation, Integration/Test, Documentation (this session).

## 1. Repository inspection

- Repo: `apple/container` @ `38fe2f9`, Swift 6.2 package, Apple-silicon only.
- `Sources/ContainerCommands/`: root `Application.swift`; `Container/` (18
  files: List/Run/Create/Start/Stop/Kill/Delete/Logs/Inspect/Stats/Exec/…),
  `Image/` (List/Pull/Push/Delete/…), `System/` (Start/Stop/Status/Version/…),
  plus Machine/Builder/Network/Volume/Registry.
- Output system: `ListFormat.swift` (`json|table|yaml|toml`, default table),
  `Output.render(payload:format:)`, `-q/--quiet`. `inspect` always pretty JSON.
- `Package.swift`: no GUI targets; `Sources/CLI/ContainerCLI.swift` is pure CLI.
- `docs/command-reference.md`: full reference (~1600 lines).
- BUILDING.md: Xcode 26, `make verify|all|test|integration|install`.
- Local `container` binary: `/opt/homebrew/opt/container/bin/container`,
  v1.2.1, `system status` → `{"status":"unregistered"}` (service not running).

## 2. Key discoveries (from research agents)

- **JSON output exists**: `container list --all --format json`,
  `container image list --format json`,
  `container system status --format json` — GUI parses these, no text scraping.
- Default `container list` shows only running; GUI must pass `--all`.
- `container stop` prints IDs, supports `--time`; `rm` alias of `delete`;
  no `restart` subcommand (GUI does stop+start); `stats` needs `--no-stream`
  for snapshots; `image pull` needs `--progress plain` for GUI capture.
- Errors → stderr + non-zero exit, e.g. XPC `Connection invalid` + "Ensure
  container system service has been started". Daemon-down must be a friendly
  empty/error state, not a crash.
- XPC (`ContainerXPC`, Mach service `com.apple.container.apiserver`) is
  Swift-only, private, entitlement-gated — Python cannot use it directly.
  **CLI subprocess is the only viable boundary.**
- Tkinter availability: Homebrew python3.12 → `No module _tkinter`;
  `/usr/bin/python3` (3.9.6) → Tk 8.5 works. Prototype-viable, not shippable.
- GUI history (`gh` search): 4 closed issues (#1925 open-API-for-GUIs,
  #1069/#111 run-GUI-apps-in-containers, #348 App-Sandbox GUI), zero open GUI
  issues/PRs, zero GUI files in repo. **No duplication risk.**

## 3. Implementation milestones

1. Created branch `feat/container-gui`.
2. Created isolated `GUI/` tree: `src/{models,cli,app}.py`, `Usage.py`,
   `tests/test_cli_parsing.py`, `requirements.txt`, `README.md`, `logs/`.
3. `models.py`: tolerant `ContainerInfo/ImageInfo/SystemStatus` dataclasses.
4. `cli.py`: `ContainerService` — binary discovery (`CONTAINER_CLI`
   override), allowlist validation, `run_raw` (argv arrays, timeouts, caps),
   list/start/stop/restart/rm/logs/inspect/run/images/pull/system methods,
   daemon-down hints.
5. `app.py`: Tkinter/ttk `App` — Containers/Images/System tabs + Command
   Output pane, worker-thread queue + `after()` pump, confirmations, empty/
   loading/error states.
6. `Usage.py`: python/tkinter/container checks, service probe, launcher.
7. `tests/`: unittest suite (validation, models, parsing, live probe).
8. Docs: `README.md`, `logs/{architecture,testing}.md`, this file,
   `logs/pr-description.md`.

## 4. Decisions

- Tkinter **accepted** for MVP per task's "Tkinter first" order: CLI JSON
  boundary is sufficient for the required dashboard/actions/images/system/
  output scope; `Usage.py` contract implies Python; SwiftUI would break
  isolation and scope. Limitations documented honestly.
- Single worker slot (one op at a time) to keep threading simple and safe.
- `restart` = stop+start; `run` = detached + optional `--name` only
  (no free-form flags → no injection surface).

## 5. Problems encountered

- HB Python missing `_tkinter` → `Usage.py` detects and suggests
  `/usr/bin/python3 Usage.py`; README documents it.
- Daemon `unregistered` on dev machine → GUI and tests must handle
  service-down gracefully (hint text, probe tests pass either way).
- `refresh_system(silent)` racing other refreshes at startup → guarded with
  busy-check so startup chain doesn't deadlock the single worker slot.
- No display in SSH/CI → GUI launch itself can't be screenshotted here;
  recorded honestly in `testing.md` instead of fabricating.

## 6. Agent contributions

- Repository Research Agent: command table, JSON format findings, binary probe.
- Architecture Research Agent: XPC analysis, Tkinter verdict, boundary
  recommendation, security notes.
- GUI History Agent: issue/PR search, no-duplication verdict.
- Implementation/Test/Docs: this session (single coherent pass for file
  consistency).

## 7. Final state

- All code under `GUI/`; no existing repo files modified.
- Branch `feat/container-gui`, local only, human commits per milestone.
- Tests: `python3 -m unittest discover -s GUI/tests -v` (see testing.md).
- Demo: `cd GUI && python3 Usage.py` (or `/usr/bin/python3 Usage.py`).
