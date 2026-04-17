# Deploy Finalization

## Overview
- Finalize deploy pipeline: replace shell `mkdir` with a proper builtin, add IDE generation to deploy, add post-deploy summary phase, implement deploy reporter layer (plain + TUI), and write curated config documentation
- Solves remaining deploy gaps: `create-dirs` is still a raw shell command, `render ide` is disconnected from deploy, deploy output has no structured reporting, and config system lacks documentation
- All changes span two repos: `next-laravel` (config/YAML) and `devbox-cli` (Go implementation). Both need feature branches and commits at each stage

## Context (from discovery)
- Files/components involved:
  - `devbox/deploy/main.yml`, `devbox/deploy/second.yml` — service deploy pipelines (contain `run: mkdir -p ...`)
  - `devbox/deploy.yml`, `devbox/reset.yml` — orchestrator pipelines
  - `devbox/services.yml` — service definitions (needs `dirs` field)
  - `devbox-cli/internal/builtin/` — builtin registry (`builtin.go`, `configs_copy.go`, etc.)
  - `devbox-cli/internal/command/pipeline.go` — step execution and pipeline lifecycle
  - `devbox-cli/internal/command/deploy.go`, `reset.go` — deploy/reset commands
  - `devbox-cli/internal/command/ide.go` — `devbox render ide` implementation
  - `devbox-cli/internal/config/devbox.go` — `ServiceConfig`, `DeployPhase`, `DeployStep` structs
  - `devbox-cli/internal/render/` — current ANSI output writer
  - `devbox-cli/internal/ui/` — Lipgloss styled output, bubbletea selectors
  - `docs/reference/config/` — does not exist yet
- Related patterns:
  - Builtins implement `Builtin` interface: `Validate`, `Describe`, `Run` with `ExecContext`
  - `ExecContext` carries `Config`, `ProjectRoot`, `Output`, `LogWriter`, `SkipConfirm`
  - Steps dispatched by type in `execStep`: `run:` (shell), `devbox:` (CLI), `command:` (registry), `builtin:` (Go)
  - Deploy output: phase labels, `[N/M]` step progress, Done/Skipped/Failed messages
  - Child processes get real `os.Stdin/os.Stdout/os.Stderr` (no capture)
  - Logs teed to `logs/deploy.log` with ANSI stripped

## Development Approach
- **Testing approach**: Regular (code first, then tests)
- Complete each task fully before moving to the next
- Make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
- **CRITICAL: all tests must pass before starting next task** — no exceptions
- **CRITICAL: update this plan file when scope changes during implementation**
- **CRITICAL: devbox-cli is a separate repo — create feature branch, commit at each task, include code review**
- Run tests after each change (`cd devbox-cli && make test`)
- Maintain backward compatibility

## Testing Strategy
- **Unit tests**: required for every task (see Development Approach above)
- Go table-driven tests following existing patterns in `devbox-cli/`
- Test builtins via `Run()` with mock `ExecContext`
- Test reporter interface via event sequence assertions
- Test TUI reporter with terminal capability detection edge cases
- Test config loading for new fields (`dirs`, `phase.ui`)

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with + prefix
- Document issues/blockers with ! prefix
- Update plan if implementation deviates from original scope

## What Goes Where
- **Implementation Steps** (`[ ]` checkboxes): tasks achievable within this codebase
- **Post-Completion** (no checkboxes): manual verification, external checks
- **Checkbox placement**: only in Task sections

## Implementation Steps

### Task 1: Add `dirs` field to ServiceConfig and services.yml
- [x] Add `Dirs []string` field to `ServiceConfig` in `devbox-cli/internal/config/devbox.go`
- [x] Update service inheritance merge in `LoadServicesConfig` to merge parent+child dirs (deduplicated)
- [x] Add `dirs: [logs, home, runtime]` to `main` service in `devbox/services.yml`
- [x] Add `dirs` to `second` service in `devbox/services.yml` (inherits from main or declares own)
- [x] Write tests for `Dirs` field loading and inheritance merge (success + edge cases)
- [x] Write tests for deduplication of dirs across parent/child
- [x] Run tests — must pass before next task

### Task 2: Implement `service_dirs_ensure` builtin
- [x] Create `devbox-cli/internal/builtin/dirs_ensure.go`
- [x] Implement `Builtin` interface: `Validate`, `Describe`, `Run`
- [x] Parameters: `service` (required), `mode` (optional: `skip`|`error`|`recreate`, default `skip`)
- [x] Behavior: resolve service from config, build full dir list (mandatory `src`, `configs` + configured `dirs`), deduplicate, resolve relative to service `dir`
- [x] `skip` mode: create missing dirs, skip existing
- [x] `error` mode: fail if any path exists and is not a directory
- [x] `recreate` mode: remove and recreate dirs (except `src` and `configs` which use `skip` semantics in `recreate` mode for safety — document this)
- [x] Register `service_dirs_ensure` in builtin registry
- [x] Write tests for all three modes (success cases)
- [x] Write tests for error cases: missing service, path-is-file conflict, security validation (no `..`, no absolute paths)
- [x] Run tests — must pass before next task

### Task 3: Replace `create-dirs` shell commands in deploy YAML
- [x] Update `devbox/deploy/main.yml`: replace `run: mkdir -p ...` step with `builtin: service_dirs_ensure` + `with: { service: main }`
- [x] Update `devbox/deploy/second.yml`: same replacement for second service
- [x] Verify `devbox deploy plan` output reflects the new builtin steps
- [x] Run tests — must pass before next task

### Task 4: Implement `builtin: message`
- [x] Create `devbox-cli/internal/builtin/message.go`
- [x] Implement `Builtin` interface
- [x] Parameters: `level` (required: `info`|`success`|`warning`|`error`), `text` (required)
- [x] Behavior: delegate to `ExecContext.Output` methods (`Success`, `Info`, `Warning`, `Error`)
- [x] Support Go template expressions in `text` field (evaluate against `DevboxConfig`)
- [x] Register `message` in builtin registry
- [x] Write tests for all four levels
- [x] Write tests for template evaluation in text
- [x] Write tests for validation errors (missing level, invalid level, missing text)
- [x] Run tests — must pass before next task

### Task 5: Add `post-deploy` phase and `finalize` phase to deploy pipelines
- [x] Add `phase.UI` field (`string`, yaml `ui`) to `DeployPhase` struct: values `plain`|`inherit`, default `inherit`
- [x] Add `post-deploy` phase to `devbox/deploy.yml` with `ui: plain`:
  - step `info`: `devbox: "info"`
  - step `success`: `builtin: message` with `level: success`, `text: Deploy completed successfully`
- [x] Add `finalize` phase to `devbox/deploy/main.yml`:
  - step `render-ide`: `devbox: "render ide main"`
- [x] Add `finalize` phase to `devbox/deploy/second.yml`:
  - step `render-ide`: `devbox: "render ide second"`
- [x] Implement `post-deploy` semantics: phase executes only if all prior phases succeeded (skip on any failure)
- [x] Verify `devbox deploy plan` shows new phases and steps
- [x] Write tests for `phase.UI` field loading
- [x] Write tests for post-deploy skip-on-failure semantics
- [x] Run tests — must pass before next task

### Task 6: Define reporter interface and implement PlainReporter
- [x] Create `devbox-cli/internal/pipeline/reporter.go` with `Reporter` interface:
  - `StartPipeline(name string, totalSteps int)`
  - `EnterPhase(phaseKey string, phase DeployPhase)` — phaseKey added for service prefix support
  - `SkipPhase(phaseKey string, phase DeployPhase, reason string)`
  - `StartStep(stepAddr string, step DeployStep, index int, total int)` — stepAddr added for full address
  - `SkipStep(stepAddr string, step DeployStep, index int, total int, reason string)`
  - `FinishStep(stepAddr string, step DeployStep, index int, total int)`
  - `FailStep(stepAddr string, step DeployStep, index int, total int, err error)`
  - `FinishPipeline(success bool)`
  - `SuspendForExec()` — TUI releases terminal before external command
  - `ResumeAfterExec()` — TUI reclaims terminal after external command
- [x] Create `devbox-cli/internal/pipeline/plain.go` implementing `PlainReporter`
- [x] `PlainReporter` reproduces current deploy output format exactly (phase labels, `[N/M]` progress, Done/Skipped/Failed)
- [x] `SuspendForExec`/`ResumeAfterExec` are no-ops for PlainReporter
- [x] Write tests for PlainReporter event sequence and output format
- [x] Run tests — must pass before next task

### Task 7: Refactor deploy/reset execution to use reporter
- [ ] Extract pipeline execution logic from `pipeline.go` into a function that accepts `Reporter`
- [ ] Replace direct `render.Writer` calls in deploy execution with reporter method calls
- [ ] Wire `PlainReporter` as default for `deploy run` and `reset run`
- [ ] Ensure logging contract unchanged: pipeline events + raw child output in log, no reporter artifacts
- [ ] Verify existing deploy/reset behavior is identical (no output changes)
- [ ] Write tests verifying reporter is called with correct events in correct order
- [ ] Run tests — must pass before next task

### Task 8: Add `--ui` flag and terminal capability detection
- [ ] Add `--ui auto|plain|tui` flag to `deploy run` and `reset run` commands
- [ ] Implement terminal capability detection in `devbox-cli/internal/pipeline/detect.go`:
  - Check `os.Stdout` / `os.Stderr` / `os.Stdin` are TTY
  - Check `TERM != dumb`
  - Check common CI env vars (`CI`, `GITHUB_ACTIONS`, `JENKINS_URL`, etc.)
- [ ] `auto` mode: use TUI if terminal is capable, fall back to plain
- [ ] `plain` mode: always PlainReporter
- [ ] `tui` mode: use TUI if capable, warn and fall back to plain if not
- [ ] Respect `phase.ui: plain` — when TUI is active, plain phases bypass TUI rendering
- [ ] Write tests for terminal detection logic (TTY, dumb term, CI vars)
- [ ] Write tests for `--ui` flag resolution
- [ ] Run tests — must pass before next task

### Task 9: Implement TUIReporter
- [ ] Create `devbox-cli/internal/pipeline/tui.go` using Bubble Tea
- [ ] Minimal UI elements:
  - Pipeline name header
  - Current phase name
  - Current step with spinner
  - Progress bar (steps completed / total)
  - Compact list of recent steps with status icons (running/skipped/done/failed)
- [ ] `SuspendForExec()`: call `bubbletea.Program.ReleaseTerminal()` or equivalent to yield terminal to child process
- [ ] `ResumeAfterExec()`: reclaim terminal and redraw current state
- [ ] Handle `phase.ui: plain` — suspend TUI for the entire phase, resume after
- [ ] Do not proxy child process stdio through Bubble Tea
- [ ] TUI frames must NOT appear in log file
- [ ] Write tests for TUI reporter event handling (model updates, not visual output)
- [ ] Write tests for suspend/resume lifecycle
- [ ] Run tests — must pass before next task

### Task 10: Verify acceptance criteria
- [ ] Verify `devbox deploy plan` shows all new phases (finalize, post-deploy) and builtin steps
- [ ] Verify `devbox deploy run` with `--ui plain` produces output identical to pre-refactor
- [ ] Verify `devbox deploy run` with `--ui tui` shows progress and yields terminal for docker compose
- [ ] Verify `devbox deploy run` with `--ui auto` falls back to plain in non-TTY
- [ ] Verify `devbox reset run` works with reporter (no regressions)
- [ ] Verify `logs/deploy.log` contains pipeline events + raw output, no TUI frames
- [ ] Verify `post-deploy` phase is skipped when a prior step fails
- [ ] Run full test suite (`cd devbox-cli && make test`)
- [ ] Run linter (`cd devbox-cli && make lint`) — all issues must be fixed

### Task 11: Write config reference documentation
- [ ] Create `docs/reference/config/index.md` — overview of all config files, which are merged vs standalone, navigation
- [ ] Create `docs/reference/config/layering.md` — merge order, precedence rules, how CLI uses merged config
- [ ] Create `docs/reference/config/devbox.md` — `devbox.yml`, `defaults.yml`, `local.yml`: structure, sections, per-layer guidance
- [ ] Create `docs/reference/config/services.md` — `services.yml`: service declaration, extends, depends_on, dirs, cli config, configs
- [ ] Create `docs/reference/config/deploy.md` — `deploy.yml`, `deploy/<service>.yml`, `reset.yml`: phases, steps, when/check, builtins, post-deploy semantics
- [ ] Create `docs/reference/config/docker.md` — `docker.yml`, `docker.local.yml`: project name, args, env triggers, devbox docker vs compose boundary
- [ ] Create `docs/reference/config/styles.md` — `styles.yml`: header, palette, separator, fallback defaults
- [ ] Create `docs/reference/config/info.md` — `info.yml`: dashboard sections, template expressions, text/value/when fields
- [ ] Each page follows: purpose, load order, merge behavior, example, field reference, related commands, common pitfalls
- [ ] Run tests — must pass before next task

### Task 12: [Final] Update project documentation
- [ ] Update `CLAUDE.md` with new builtin names, reporter interface, `--ui` flag, `phase.ui` field, `dirs` in ServiceConfig
- [ ] Update `devbox/local.example.yml` if new override options exist
- [ ] Run `./bin/devbox docs generate` to refresh CLI reference docs

## Technical Details

### New config fields

**`ServiceConfig.Dirs`** (in `services.yml`):
```yaml
services:
  main:
    dirs: [logs, home, runtime]  # additional dirs beyond mandatory src, configs
```
Mandatory dirs (`src`, `configs`) are always created and not configurable. `dirs` lists additional relative paths within the service hub directory.

Inheritance: child service merges parent's `dirs` with its own (deduplicated, parent first).

### `service_dirs_ensure` builtin

Parameters:
- `service` (string, required) — service name from config
- `mode` (string, optional) — `skip` (default), `error`, `recreate`

Resolved directory list: `[src, configs] + ServiceConfig.Dirs` (deduplicated).

Mode behavior:
| Mode | Dir missing | Dir exists | Non-dir exists |
|------|-------------|------------|----------------|
| skip | create | no-op | error |
| error | create | error | error |
| recreate | create | remove+create | error |

Safety: `recreate` mode treats `src` and `configs` with `skip` semantics (never removes source code or config files).

### `message` builtin

Parameters:
- `level` (string, required) — `info`, `success`, `warning`, `error`
- `text` (string, required) — supports Go template expressions against DevboxConfig

### `DeployPhase.UI` field

```yaml
phases:
  - name: post-deploy
    ui: plain        # plain | inherit (default)
```

When deploy runs in TUI mode and phase has `ui: plain`:
- TUI suspends before phase starts
- Steps execute with plain text output
- TUI resumes after phase completes

### Reporter interface

```
StartPipeline → [EnterPhase → [StartStep → SuspendForExec → ResumeAfterExec → FinishStep|FailStep|SkipStep]... → SkipPhase?]... → FinishPipeline
```

Two implementations:
- `PlainReporter` — identical to current output (phase labels, `[N/M]` progress)
- `TUIReporter` — Bubble Tea minimal progress UI with terminal yield for external commands

### Terminal detection for `--ui auto`

Falls back to plain if ANY of:
- `os.Stdout` is not a TTY
- `os.Stderr` is not a TTY
- `os.Stdin` is not a TTY
- `TERM=dumb`
- `CI=true` or `GITHUB_ACTIONS`, `JENKINS_URL`, `BUILDKITE`, `GITLAB_CI` set

### Post-deploy semantics

`post-deploy` phase name is conventional (not magic). Implementation: if any step in any prior phase fails, remaining phases (including post-deploy) are skipped. This is already the current behavior — deploy aborts on first failure. The `post-deploy` phase simply benefits from being last.

### Logging contract

Log file (`logs/deploy.log`, `logs/reset.log`) contains:
- Pipeline events (phase entry, step start/finish/skip/fail)
- Raw child process stdout/stderr

Log file does NOT contain:
- TUI frames or redraw sequences
- ANSI escape codes (already stripped)

## Post-Completion
*Items requiring manual intervention or external systems — no checkboxes, informational only*

**Manual verification**:
- Run full deploy cycle (`make deploy`) and verify directory creation, IDE config generation, and post-deploy summary
- Run deploy in non-TTY context (pipe to file) and verify plain fallback
- Run reset cycle (`make deploy-reset`) and verify reporter integration
- Test with `TERM=dumb` to verify CI fallback
- Visual check of TUI reporter appearance and terminal yield during `docker compose` steps

**Cross-repo coordination**:
- devbox-cli feature branch must be created and committed at each task boundary
- next-laravel YAML changes must be committed alongside or after CLI changes
- Final merge: CLI first, then config repo
