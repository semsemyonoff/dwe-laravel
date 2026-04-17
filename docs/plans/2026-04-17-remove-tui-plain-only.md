# Remove TUI Reporter — Plain Only Mode

## Overview
- Remove the TUI (Bubble Tea) reporter from the deploy/reset pipeline. TUI mode works poorly and is hard to maintain.
- Keep only PlainReporter as the single output mode (no `--ui` flag, no mode selection).
- Enhance PlainReporter with icons (✓ ✗ ◎ ·) from the old TUI, suppress output for untracked phases, fix color passthrough for `devbox info` step, and add total elapsed time to the final "Done" message.
- Remove `ui` field from deploy/reset phase config.
- Move `docs/reference/config/` documentation into the `devbox-cli` repository (it belongs there, not in the pilot project).

## Context
- **Reporter system**: `internal/pipeline/` — `Reporter` interface, `PlainReporter`, `TUIReporter`, `detect.go` (UIMode, ParseUIMode, NewReporter, IsCapableTTY)
- **TUI reporter**: `internal/pipeline/tui.go` + `tui_test.go` — Bubble Tea model, icons (✓ ✗ ◎ ·), progress bar, terminal suspend/resume
- **Plain reporter**: `internal/pipeline/plain.go` — text output via render.Writer, no icons currently
- **Config**: `DeployPhase.UI` field in `internal/config/devbox.go:84`, `DeployPhase.Untracked` at line 85
- **Deploy command**: `--ui` flag in `internal/command/deploy.go:318` and `reset.go:129`
- **Pipeline executor**: `internal/command/pipeline.go` — `runPipeline()` has TUI-specific confirm wiring (line 405)
- **Info color issue**: `execStep()` sets `cmd.Stdout = io.MultiWriter(os.Stdout, logStripped)` — child process sees a pipe, not a TTY → lipgloss disables colors for everything except raw ANSI (ASCII art)
- **Styles config**: `progress_bar` color in `StylesColors` / `ui.ProgressBarColor()` — only used by TUI
- **bubbletea/bubbles deps**: Also used by `internal/ui/selector.go` (interactive pickers) — keep in go.mod
- **Docs**: `docs/reference/config/` exists in pilot repo root, should move to devbox-cli repo
- **Both repos**: devbox-cli is a separate repo (`devbox-cli/`), commits happen in both repos during implementation

## Development Approach
- **Testing approach**: Regular (code first, then tests)
- Complete each task fully before moving to the next
- Make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- Run tests after each change
- Maintain backward compatibility for config loading (unknown YAML fields should not error)

## Testing Strategy
- **Unit tests**: required for every task (see Development Approach above)
- Run `cd devbox-cli && make test` after each task

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Update plan if implementation deviates from original scope

## Implementation Steps

### Task 1: Remove TUI reporter and detect.go simplification (devbox-cli)
- [x] Delete `internal/pipeline/tui.go`
- [x] Delete `internal/pipeline/tui_test.go`
- [x] Simplify `internal/pipeline/detect.go`: remove `UIModeAuto`, `UIModeTUI`, `ParseUIMode`, `IsCapableTTY`, `isCapableTTYWith`, `NewReporter`. The package only needs `NewPlainReporter`.
- [x] Remove `detect_test.go` (all tests are about TUI/auto mode selection)
- [x] Update `internal/pipeline/reporter.go` doc comments — remove TUI references
- [x] Update tests for remaining pipeline package — verify PlainReporter still passes
- [x] Run `make test` — must pass before next task

### Task 2: Remove `--ui` flag and TUI wiring from deploy/reset commands (devbox-cli)
- [ ] `internal/command/deploy.go`: remove `uiFlag` variable, `ParseUIMode` call, `--ui` flag registration. Create reporter directly: `rep := pipeline.NewPlainReporter(w)`
- [ ] `internal/command/reset.go`: same removal of `uiFlag`, `ParseUIMode`, `--ui` flag. Create reporter directly.
- [ ] `internal/command/pipeline.go`: remove TUI-specific confirm wiring (lines ~404-407 checking `*pipeline.TUIReporter`). Remove `ui: plain` phase handling (line ~482 `rs.phase.UI == "plain"` check). Remove import of `pipeline` package if no longer needed (it still is for Reporter interface).
- [ ] Write/update tests for deploy run and reset run command creation (verify no `--ui` flag)
- [ ] Run `make test` — must pass before next task

### Task 3: Remove `UI` field from DeployPhase config (devbox-cli)
- [ ] `internal/config/devbox.go`: remove `UI string` field from `DeployPhase` struct
- [ ] Update any tests in `internal/config/` that reference `DeployPhase.UI`
- [ ] Run `make test` — must pass before next task

### Task 4: Add icons to PlainReporter output (devbox-cli)
- [ ] Add icon constants to `internal/pipeline/plain.go`: `✓` (done), `✗` (failed), `◎` (skipped), `·` (running/start)
- [ ] Update `StartStep()`: prefix with `·` icon — `  · [N/M] stepAddr: description`
- [ ] Update `FinishStep()`: prefix with `✓` icon — `  ✓ [N/M] Done: stepAddr`
- [ ] Update `SkipStep()`: prefix with `◎` icon — `  ◎ [N/M] Skipped: stepAddr (reason)`
- [ ] Update `FailStep()`: prefix with `✗` icon in error message
- [ ] Write tests for each icon in PlainReporter output
- [ ] Run `make test` — must pass before next task

### Task 5: Suppress output for untracked phases in PlainReporter (devbox-cli)
- [ ] `PlainReporter.EnterPhase()`: if `phase.Untracked`, return early (no phase header)
- [ ] `PlainReporter.SkipPhase()`: if `phase.Untracked`, return early
- [ ] `PlainReporter.StartStep()`: if `index == 0 && total == 0` (untracked), return early (no step message)
- [ ] `PlainReporter.FinishStep()`: same — suppress for untracked
- [ ] `PlainReporter.SkipStep()`: same — suppress for untracked
- [ ] `PlainReporter.FailStep()`: keep failure output even for untracked (failures should always be visible)
- [ ] Write tests for untracked suppression (phase header, step start/done/skip all silent; fail still prints)
- [ ] Run `make test` — must pass before next task

### Task 6: Fix color passthrough for `devbox info` in deploy pipeline (devbox-cli)
- [ ] In `execStep()` (`internal/command/pipeline.go`): when step is `devbox:` type, pass `cmd.Stdout = os.Stdout` and `cmd.Stderr = os.Stderr` directly (TTY preserved). Write to logWriter separately by reading from a pipe or teeing after the fact. Alternative: set `CLICOLOR_FORCE=1` env var on the child process so lipgloss detects color support.
- [ ] Verify that log file still receives ANSI-stripped output
- [ ] Write test verifying child process inherits real stdout (or env var is set)
- [ ] Run `make test` — must pass before next task

### Task 7: Add elapsed time to Done message (devbox-cli)
- [ ] Add `startTime time.Time` field to `PlainReporter`
- [ ] In `StartPipeline()`: record `time.Now()`
- [ ] In `FinishPipeline(success bool)`: if success, print styled "Done" message with elapsed time (e.g. `✓ Done (1m 23s)`). Use `r.w.Success()` for the icon/Done part. Print elapsed time in a visually distinct (muted) style.
- [ ] Update `deploy.go` and `reset.go` to rely on `FinishPipeline` for the Done message (currently they print log path after pipeline — keep log path, add Done before it)
- [ ] Write tests for FinishPipeline output (success with time, failure no Done)
- [ ] Run `make test` — must pass before next task

### Task 8: Remove `progress_bar` from StylesColors config (devbox-cli)
- [ ] `internal/config/styles.go`: remove `ProgressBar` field from `StylesColors`
- [ ] `internal/ui/styles.go`: remove `progressBarColor` variable, `ProgressBarColor()` func, and the `if c.ProgressBar != ""` block in `ApplyStyles`
- [ ] Update/remove tests for progress bar color in `styles_test.go` and `config/styles_test.go`
- [ ] Run `make test` — must pass before next task

### Task 9: Remove `ui: plain` from deploy.yml config (next-laravel)
- [ ] `devbox/deploy.yml`: remove `ui: plain` from post-deploy phase
- [ ] Verify `untracked: true` remains on post-deploy phase (controls output suppression now)

### Task 10: Move docs/reference/config/ to devbox-cli repo
- [ ] Copy `docs/reference/config/` files into `devbox-cli/docs/reference/config/`
- [ ] Update content: remove references to TUI mode, `--ui` flag, `ui:` phase field, `progress_bar` style
- [ ] Remove `docs/reference/config/` from the next-laravel repo
- [ ] Commit in both repos

### Task 11: Update CLAUDE.md documentation (next-laravel)
- [ ] Remove TUI references: `TUIReporter`, `DetectReporter`, `--ui auto|plain|tui`, Bubble Tea progress UI
- [ ] Remove `UI string` from `DeployPhase` description
- [ ] Remove `progress_bar` from `StylesColors` description
- [ ] Update `DeployPhase` description: remove `ui: plain|inherit` explanation
- [ ] Update pipeline package description: only PlainReporter, no TUI
- [ ] Keep `bubbletea` and `bubbles` in dependencies list (still used by selector)
- [ ] Remove `terminal yield` and `TUI` references from `TUIReporter` mentions in pipeline description

### Task 12: Verify acceptance criteria
- [ ] Verify: `devbox deploy run` works with plain output only (no `--ui` flag)
- [ ] Verify: icons appear in step output (✓ ✗ ◎ ·)
- [ ] Verify: untracked phase produces no system messages
- [ ] Verify: `devbox info` shows full colors when run as deploy step
- [ ] Verify: Done message shows elapsed time in distinct style
- [ ] Verify: `ui:` field in YAML is silently ignored (no parse error)
- [ ] Run full test suite (unit tests)
- [ ] Run linter — all issues must be fixed

### Task 13: [Final] Update documentation
- [ ] Update README.md if needed
- [ ] Verify docs/reference/config/ is correct in devbox-cli

## Technical Details

### Icon format in PlainReporter
```
  · [1/12] main/setup/create-dirs: Create service hub directories
  ✓ [1/12] Done: main/setup/create-dirs
  ◎ [2/12] Skipped: main/setup/install (when: dir-empty services/main/src)
  ✗ Deploy failed at step "main/init/migrate"
```

### Done message format
```
  ✓ Done (1m 23s)                    ← Success() styled, time in muted style
  Deploy log saved to: logs/deploy.log  ← Info() styled, as before
```

### Info color fix approach
The issue: `execStep()` wraps cmd.Stdout in `io.MultiWriter(os.Stdout, logStripped)`. The child process (devbox info) sees a pipe, not a TTY. Lipgloss v2 detects this and disables colors.

Fix: set `CLICOLOR_FORCE=1` in the child process environment. This is a well-known convention that lipgloss respects. Log teeing still works via MultiWriter — the ansiStripper handles ANSI removal for the log file.

### Untracked detection in PlainReporter
Untracked steps receive `index=0, total=0` from `runPipeline()`. PlainReporter checks this to suppress output. The `phase.Untracked` bool is passed via `EnterPhase(phaseKey, phase)` for phase-level suppression.

## Post-Completion
- Manual testing: run full deploy and reset on a real project
- Verify reset pipeline still works with confirm builtin (stdin-based, no TUI)
