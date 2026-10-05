# Architecture — container GUI contribution

## Decision: Tkinter accepted for MVP (SwiftUI deferred)

### Why Tkinter was evaluated

Task order requires Tkinter first if it can "realistically provide a
functional and reasonably polished macOS GUI" as a frontend over the
existing CLI/API, without reimplementing container functionality.

### Why Tkinter was accepted (for this prototype scope)

1. **Integration is clean.** The CLI exposes everything the MVP needs via
   stable flags: `list --all --format json`, `image list --format json`,
   `system status --format json`, plus start/stop/rm/logs/inspect/pull and
   `system start/stop/version`. A thin `ContainerService` adapter over
   argv-array subprocess covers Dashboard/Actions/Images/System/Output with
   zero Swift/XPC code and zero changes to existing sources.
2. **Contract fit.** The assignment requires `python3 Usage.py` to launch
   the demo and an isolated directory. Tkinter (stdlib) satisfies both with
   no dependencies; SwiftUI would need a new Swift target, entitlements, and
   a different demo command.
3. **Risk/scope.** A native client must speak private Mach-service XPC
   (`ContainerXPC`, `com.apple.container.apiserver`, fd-passing, progress
   endpoints) or re-implement CLI parsing in Swift — correct but far beyond
   a "lightweight frontend for the most common workflows".

### Why SwiftUI was NOT selected now (honest limitations)

- Tk 8.5 (system Python) looks dated: weak Dark Mode, accessibility, and
  menu-bar/dock integration vs SwiftUI/AppKit.
- Fragile interpreter story: Homebrew Python 3.12 here lacks `_tkinter`;
  system Python 3.9 works but pins the demo to a deprecated runtime.
- No streaming/TTY (`logs -f`, `stats` streaming, `exec`, vsock `dial()`,
  progress APIs) without manual thread plumbing; Swift `async/await` + XPC
  would be first-class.
- No notarized `.app` packaging story.

**Switch to SwiftUI when**: native look/a11y, App Store/notarized
distribution, streaming logs/stats/exec, or escaping the system-Python
lock-in become requirements. The CLI-adapter schema (models + action set)
maps 1:1 onto a future `ContainerClient`-backed SwiftUI app.

### Considered and rejected

- **Direct XPC/gRPC from Python**: infeasible — Swift-only libxpc Mach
  handshake, dictionary protocol, fd-passing, code-signing/entitlements;
  private and unstable. Rejected by Architecture Agent.
- **Web UI (local HTTP + browser)**: out of scope ("native GUI"), adds a
  server/attack surface, violates the Tkinter-first requirement. Rejected.

## Integration mechanism

```text
App (tkinter/ttk, main thread only)
  │ method calls
  ▼
ContainerService (GUI/src/cli.py) — SOLE subprocess owner
  │ subprocess.run([binary, *args], shell=False, timeout, caps)
  ▼
`container` CLI (signed, supported boundary; --format json preferred)
  │ XPC (unchanged, Apple-owned)
  ▼
apiserver / runtime / VMs
```

- UI never blocks: worker thread → `queue.Queue` → `root.after(100)` pump.
- One operation at a time (`busy` flag) — simple, race-free.
- `run_raw` echoes every invocation to the Command Output pane.

## Separation of concerns

| File | Responsibility | May import |
|---|---|---|
| `src/models.py` | JSON → view-model dataclasses | stdlib only |
| `src/cli.py` | binary discovery, validation, subprocess, errors | models, stdlib |
| `src/app.py` | widgets, threads→UI marshalling, dialogs | cli, models, tkinter |
| `Usage.py` | env checks + launch | src.* |
| `tests/` | validation/parsing/live-probe | src.* |

`app.py` never builds argv; `cli.py` never touches widgets.

## Security considerations

- **No `shell=True`, no `os.system`, no string-built commands** — ever.
  Absolute binary path + argv list via `subprocess.run`.
- **Allowlist validation** (`^[A-Za-z0-9_.\-/:@]+$`, ≤256 chars) on every
  user-controlled operand (IDs, names, image refs) before subprocess;
  violations raise `ValueError` before any spawn.
- **No free-form flags**: `run_container` accepts image + optional name
  only; extra flags rejected (prevents `--privileged`-style smuggling and
  flag-injection via values starting with `-`... note: values are validated
  to exclude leading `-`? `-` is allowed mid-string but a value of exactly
  `-x` would match the regex; mitigated because operands are always placed
  after subcommand positionally and image/name positions never parse as
  flags... future hardening: insert `--` separator).
- Env override `CONTAINER_CLI` honored but must resolve to an executable
  file; `PATH` lookup via `shutil.which` (no custom shell PATH munging).
- Timeouts on all calls (default 30s; pull 600s; system start 180s),
  512 KiB output caps, UTF-8 `errors="replace"`, no secrets logged
  (no tokens/passwords pass through this GUI at all).
- Destructive actions (remove, restart, system start/stop) require
  confirmation dialogs; `system stop` warns about running containers.
- Daemon-down output is detected and augmented with a safe, static hint
  (no reflection of attacker-controlled paths).
