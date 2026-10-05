# Testing — container GUI contribution

All results below were actually observed on the dev machine
(macOS 27.0.1 arm64, container 1.2.1, daemon `unregistered`).
Nothing is fabricated. Live container lifecycle (start/stop a real
container) was NOT exercised because the system service is stopped — see
§6 for exactly what that means for the demo.

## 1. Automated unit + probe tests

Command: `python3 -m unittest discover -s GUI/tests -v`
(also verified with `/usr/bin/python3`)

Result: **12/12 pass** on both interpreters (homebrew 3.12.14 and system 3.9.6).

| Test | Expected | Actual |
|---|---|---|
| `test_valid_ids` | allowlisted ids/refs accepted | PASS |
| `test_rejects_shell_metachars` (`; $() `` \| &` quotes, spaces, backslash, `>`) | `ValueError` before any spawn | PASS |
| `test_rejects_too_long` (300 chars) | `ValueError` | PASS |
| `test_image_ref` | valid accepted, `;`-payload rejected | PASS |
| `test_container_from_dict` (+`ID`/`Status` case variants) | tolerant mapping, `is_running` correct | PASS |
| `test_image_from_dict` | `reference == name:tag` | PASS |
| `test_system_status` | running vs unregistered | PASS |
| `test_parse_json_array` / `test_parse_json_object` | round-trip; `""` → empty; bad JSON raises | PASS |
| `test_daemon_hint` | hint string detected | PASS |
| `test_binary_present_and_help_works` (live) | binary found, `--help` exit 0 | PASS |
| `test_system_status_probe` (live) | parses `unregistered` (daemon down) without crash | PASS |

Byte-compile: `py_compile` on all 5 Python files → OK.

## 2. `Usage.py` diagnostics

- `python3 GUI/Usage.py --check` (HB 3.12): `[OK] Python`, `[!!] Tkinter
  NOT available: No module named '_tkinter'` + suggests
  `/usr/bin/python3 Usage.py`, `[OK] container …`, service probe shows
  `{"status":"unregistered"}`. Exit 1 (correct: refuses to launch).
- `/usr/bin/python3 GUI/Usage.py --check`: all `[OK]`, "All checks passed
  (check-only mode)". Exit 0.

## 3. Real CLI error paths (daemon stopped — the "system unavailable" case)

| Command (real binary) | Expected | Actual |
|---|---|---|
| `container list --all --format json` | daemon-down error mentioning `container system start` | `Error: internalError: "failed to list containers" … Connection invalid. Ensure container system service has been started…` — matches adapter's `_daemon_down_hint` markers |
| `container image list --format json` | same class of error | `Error: interrupted: XPC connection error… Ensure container system service has been started…` |
| `container stop does-not-exist-123` | clear failure, no hang | `failed to stop container … Connection invalid … system start` |
| `container system status --format json` | JSON with non-running status, exit ≠ 0 | `{"status":"unregistered",…}`, exit 1 — GUI parses `status` field and shows `System: unregistered` |

GUI-side handling (code-verified, worker-thread path): daemon-down raises
`ContainerCLIError` with the CLI message + static hint, shown in a dialog
AND appended to the Command Output pane; app stays responsive (no mainloop
block; single `busy` slot).

## 4. GUI launch

- Headless SSH session here has no window server, so `Usage.py` full launch
  (opening a `Tk()` window) was NOT executed on this machine — attempting it
  would fail with a display error, not an app bug. `Usage.py` handles that
  case with a "needs a macOS graphical session" message.
- Widget code path verified by import + construction review and `py_compile`;
  screenshots not bundled (see README). **Demo on a graphical Mac with
  `/usr/bin/python3 GUI/Usage.py`.**

## 5. Original repository unaffected

- `git status --short` → only `?? GUI/` (no tracked-file modifications).
- `container --help`, `list/image list/system status|version --help`,
  `system version` all still work (used during research).
- Full `make test` / Swift suite NOT run (VM-booting integration suite is
  out of scope for a zero-Swift-change additive contribution; nothing in
  `Sources/`/`Tests/` was touched).

## 6. Honest gaps / what the demonstrator should do

1. **Start the service first**: `container system start`, then
   `cd GUI && /usr/bin/python3 Usage.py`.
2. **Live lifecycle demo** (needs service up): `container run -d --name
   demo alpine sleep 300` → see it in dashboard → Stop via GUI → Start via
   GUI → Remove via GUI → `container image pull alpine:latest` via Images
   tab → `container system stop` via System tab (shows empty/error states).
3. These flows were code-reviewed against verified `--help` signatures and
   JSON formats but not click-tested here because the daemon is down and
   booting VMs was out of scope for this pass.

## 7. Final status

- Automated tests: PASS (12/12, both interpreters).
- Diagnostics: PASS (correct OK / [!!] behaviour per interpreter).
- Error/empty/system-down states: verified against REAL daemon-down CLI
  output (not mocks).
- Live start/stop against a running daemon: NOT performed (documented gap).
- Repo contamination: NONE (`GUI/` only).
