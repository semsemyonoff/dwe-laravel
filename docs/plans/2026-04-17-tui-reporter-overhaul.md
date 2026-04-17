# TUI Reporter Overhaul

## Overview
- Overhaul the Bubble Tea TUI reporter for deploy/reset pipelines to fix bugs and improve UX
- **Problems**: broken confirm prompt (escape codes leak), no completed step history, broken log file output, ugly progress bar, no elapsed timer, untracked phases counted in progress
- **Result**: polished TUI with charmbracelet/bubbles progress bar, elapsed timer, completed step history, native Bubble Tea confirmation, correct log file output, and `untracked` phase support

## Context (from discovery)
- **TUI Reporter**: `devbox-cli/internal/pipeline/tui.go` — Bubble Tea model with custom ASCII progress bar, spinner, recent steps (capped at 5)
- **Plain Reporter**: `devbox-cli/internal/pipeline/plain.go` — line-by-line text output via render.Writer
- **Reporter interface**: `devbox-cli/internal/pipeline/reporter.go` — lifecycle contract (StartPipeline, EnterPhase, StartStep, etc.)
- **Confirm builtin**: `devbox-cli/internal/builtin/confirm.go` — uses `render.Writer.Confirm()` which calls `fmt.Fscan(os.Stdin)`, conflicts with Bubble Tea owning stdin
- **Pipeline runner**: `devbox-cli/internal/command/pipeline.go` — `runPipeline()` orchestrates steps, calls SuspendForExec/ResumeAfterExec around each step
- **Log handling**: deploy/reset commands create `io.MultiWriter(os.Stdout, &ansiStripper{logFile})` — but TUI frames (Bubble Tea View output) are written to terminal, not through this writer. Currently log files capture TUI escape sequences when terminal is suspended
- **Config structs**: `DeployPhase` in `devbox-cli/internal/config/devbox.go` — has `UI string` field but no `Untracked` field
- **Styles**: `devbox/styles.yml` — ANSI 256-color palette (coral red theme), no progress bar color defined
- **Dependencies**: bubbletea v2.0.5, lipgloss v2.0.3 — but **no charmbracelet/bubbles** dependency yet

## Development Approach
- **Testing approach**: Regular (code first, then tests)
- Complete each task fully before moving to the next
- Make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- **CRITICAL: devbox-cli is a separate repo — create feature branch, commit at each task, include code review**
- Run tests after each change
- Maintain backward compatibility with plain reporter

## Testing Strategy
- **Unit tests**: required for every task
- Focus on model state transitions (Update), view output (View), config parsing, and log file content

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Update plan if implementation deviates from original scope

## Implementation Steps

### Task 1: Add `untracked` field to DeployPhase config
Add `Untracked bool` field so phases like `post-deploy` are excluded from progress counting.

- [x] Add `Untracked bool` field with `yaml:"untracked"` tag to `DeployPhase` in `internal/config/devbox.go`
- [x] Set `untracked: true` on `post-deploy` phase in `devbox/deploy.yml`
- [x] Update `runPipeline()` in `internal/command/pipeline.go` to compute `trackedTotal` (excluding untracked phase steps) and pass that to `rep.StartPipeline()` instead of `len(steps)`
- [x] Update `runPipeline()` to skip incrementing step index for untracked steps in reporter calls (or pass a flag)
- [x] Write tests for config loading with `untracked: true` field
- [x] Write tests for tracked step count computation in pipeline
- [x] Run tests — must pass before next task

### Task 2: Add charmbracelet/bubbles dependency and progress bar color to styles
- [x] Add `charm.land/bubbles/v2` dependency to `go.mod` (`go get charm.land/bubbles/v2`)
- [x] Add `progress_bar` color field to `StylesColors` struct in `internal/config/styles.go`
- [x] Add `progress_bar: "203"` (coral red, matching theme) to `devbox/styles.yml`
- [x] Wire the progress bar color into `ui.ApplyStyles()` so it's accessible at runtime
- [x] Write tests for styles config loading with new `progress_bar` field
- [x] Run tests — must pass before next task

### Task 3: Rewrite TUI model with bubbles progress bar and stopwatch
Replace the custom ASCII progress bar with `bubbles/progress` and add elapsed time display with `bubbles/stopwatch`.

- [x] Import `charm.land/bubbles/v2/progress` and `charm.land/bubbles/v2/stopwatch` in `tui.go`
- [x] Replace custom `spinnerFrames` with `charm.land/bubbles/v2/spinner` (Dot or MiniDot style)
- [x] Add `progress.Model` field to `tuiModel` — configure with `progress.WithColors()` using the progress bar color from styles
- [x] Add `stopwatch.Model` field to `tuiModel` — started by Init()
- [x] Remove custom `progressBar()` function, use `progress.Model.ViewAs(percent)` instead
- [x] Update `Init()` to batch spinner, stopwatch, and progress tick commands
- [x] Update `Update()` to forward messages to spinner, stopwatch, and progress sub-models
- [x] Update `View()` to render: title + timer, phase, progress bar + count, spinner + current step, completed steps list
- [x] Write tests for model Init/Update state transitions with new sub-models
- [x] Write tests for View output format (title, timer placeholder, progress bar, step list)
- [x] Run tests — must pass before next task

### Task 4: Show completed step history in TUI (plain-style formatting)
Expand the recent steps display to show all completed/skipped/failed steps with plain-style formatting.

- [x] Remove `maxRecentSteps` cap — store all completed steps (pipelines are finite, typically <20 steps)
- [x] Update `tuiStepRecord` to include `index`, `total`, and `reason` (for skip reason display)
- [x] Update `View()` to render completed steps in plain-reporter style: `✓ [N/M] Done: addr`, `◎ [N/M] Skipped: addr (reason)`, `✗ [N/M] Failed: addr`
- [x] For untracked phase steps, display without index numbering or with separate visual treatment
- [x] Write tests for step record accumulation (no cap)
- [x] Write tests for View rendering of various step states with indices
- [x] Run tests — must pass before next task

### Task 5: Implement Bubble Tea confirmation model for TUI
Replace the plain stdin-based confirm with a native Bubble Tea confirmation within the TUI.

- [x] Create `tuiConfirmMsg` message type with `message`, `okMsg`, `stopMsg` fields
- [x] Create `tuiConfirmResponseSentMsg` (no-op Msg returned by response cmd)
- [x] Add confirmation state to `tuiModel`: `confirmActive bool`, `confirmMessage string`, etc.
- [x] Update `View()` to render confirmation prompt when `confirmActive` is true (`⚠  <message>` + `[Y]/[N]`)
- [x] Update `Update()` to handle key events (y/Y → confirm, n/N/Esc → deny) when `confirmActive`
- [x] Add `Confirm()` method to `TUIReporter` — sends `tuiConfirmMsg` and blocks on respCh
- [x] Update `builtin.ExecContext` to carry a `ConfirmFunc func(msg, okMsg, stopMsg string) (bool, error)` callback
- [x] Update confirm builtin to use `ConfirmFunc` when available (TUI mode), fall back to stdin prompt (plain mode)
- [x] Wire `ConfirmFunc` in `runPipeline()` when reporter is `*TUIReporter`; skip SuspendForExec for `builtin: confirm` in TUI mode
- [x] Write tests for confirmation model state transitions (key handling)
- [x] Write tests for confirm builtin with both ConfirmFunc and fallback paths
- [x] Run tests — must pass before next task

### Task 6: Fix log file output in TUI mode
Ensure TUI mode log files match plain mode output (no escape sequences, no Bubble Tea frames).

- [x] Identify the issue: in TUI mode, `SuspendForExec()` releases terminal, child process writes to `io.MultiWriter(os.Stdout, logStripped)` — but reporter events (phase/step start/finish) are only rendered by Bubble Tea, never reaching the log writer
- [x] Add a `logWriter` field to `TUIReporter` — receives plain-text lifecycle events for the log file
- [x] In `TUIReporter.EnterPhase()`, write `Phase: <key>[: desc]` to logWriter (matching PlainReporter format)
- [x] In `TUIReporter.StartStep()`, write `[N/M] <addr>[: desc]` to logWriter
- [x] In `TUIReporter.FinishStep()`, write `[N/M] Done: <addr>` to logWriter
- [x] In `TUIReporter.SkipStep()`, write `[N/M] Skipped: <addr> (reason)` to logWriter
- [x] In `TUIReporter.FailStep()`, write error lines to logWriter
- [x] Update `NewTUIReporter()` to accept `logWriter io.Writer` parameter
- [x] Update `NewReporter()` factory and callers (deploy.go, reset.go) to pass `logFile` to TUI reporter
- [x] Write tests that verify logWriter receives plain-formatted output for each event
- [x] Write tests that logWriter receives no ANSI sequences
- [x] Run tests — must pass before next task

### Task 7: Polish TUI view with Lipgloss styling
Apply Lipgloss styles to TUI elements using colors from styles.yml for a polished look.

- [x] Style pipeline title with `section_title` color (bold)
- [x] Style phase label with `subheader` color
- [x] Style elapsed time with `muted` color
- [x] Style step icons: `✓` with `enabled` color, `◎` with `muted`, `✗` with `warning`/red
- [x] Style current step spinner with `info` color
- [x] Style progress count (`5/12`) with `muted` color
- [x] Ensure all styled output is terminal-only (not written to logWriter)
- [x] Write tests for View output containing expected style markers
- [x] Run tests — must pass before next task

### Task 8: Verify acceptance criteria
- [x] Verify confirm prompt works in TUI without escape code garbage (manual test - skipped, not automatable)
- [x] Verify completed steps are shown above current step (plain-style formatting) (manual test - skipped, not automatable)
- [x] Verify `post-deploy` phase with `untracked: true` is not counted in progress bar (manual test - skipped, not automatable)
- [x] Verify bubbles progress bar renders with correct color from styles.yml (manual test - skipped, not automatable)
- [x] Verify elapsed timer is displayed and updates (manual test - skipped, not automatable)
- [x] Verify log files (`logs/deploy.log`, `logs/reset.log`) match plain reporter format — no TUI frames, no escape sequences (manual test - skipped, not automatable)
- [x] Run full test suite (`cd devbox-cli && make test`)
- [x] Run linter (`cd devbox-cli && make lint`) — all issues must be fixed

### Task 9: [Final] Update documentation
- [ ] Update CLAUDE.md if new patterns or config fields were added (DeployPhase.Untracked, StylesColors.ProgressBar)
- [ ] Update `devbox/styles.yml` comments if needed

## Technical Details

### New config field: `DeployPhase.Untracked`
```yaml
# devbox/deploy.yml
- name: post-deploy
  untracked: true  # excluded from progress bar and step counter
  ui: plain
```

### New styles field: `StylesColors.ProgressBar`
```yaml
# devbox/styles.yml
colors:
  progress_bar: "203"  # coral red, matching project theme
```

### TUI View Layout (compact dashboard)
```
  Deploy                          00:42
  Phase: services
  ████████████████████████████████████████  5/12
  ⠹ [5/12] start/up: Start all containers

  ✓ [1/12] Done: render-env
  ✓ [2/12] Done: main/setup/configs-copy
  ✓ [3/12] Done: main/setup/dirs-ensure
  ◎ [4/12] Skipped: main/db/create (when: ...)
```

### Confirmation in TUI
```
  ⚠️  This will stop containers, remove project volumes, and delete generated data.
  Press [Y] to confirm or [N] to cancel
```

### Log file format (identical for both TUI and plain modes)
```
Phase: pre
  [1/4] pre/confirm
  [1/4] Done: pre/confirm
Phase: stop
  [2/4] stop/down: Stop and remove all project containers
  [2/4] Done: stop/down
...
```

### Dependencies to add
- `charm.land/bubbles/v2` — progress bar, stopwatch, spinner components

## Post-Completion
*Items requiring manual intervention — no checkboxes, informational only*

**Manual verification**:
- Run `devbox reset run` and verify TUI confirmation works interactively
- Run `devbox deploy run` end-to-end and verify visual output
- Verify `logs/deploy.log` and `logs/reset.log` are clean plain text
- Test `--ui plain` still works identically to before
- Test `--ui tui` on non-TTY (should fallback gracefully)
