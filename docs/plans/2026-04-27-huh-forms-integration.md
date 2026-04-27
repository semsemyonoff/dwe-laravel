# Phase 7 — Forms with huh

## Overview

Replace the bubbletea-based interactive selector and stdin-based Y/n confirmations in `devbox-cli` with `charm.land/huh/v2` (v2.0.3) primitives. The module path is `charm.land/huh/v2` — same `charm.land` namespace already used for `bubbletea/v2` and `lipgloss/v2`, **not** `github.com/charmbracelet/huh`. Reshape the `services` and `tools` command groups around the new primitives:

- `services/tools enable` and `disable` use `huh.Select` for picking a target.
- `services/tools list` becomes an interactive `huh.MultiSelect` toggle: the form is pre-checked with currently-active items; on submit, every newly-checked item is enabled and every newly-unchecked item is disabled in `devbox/local.yml`. Mandatory services do not appear inside the form at all — they are filtered out before building options and listed separately above the form as an always-on header. (huh v2 does not expose a per-option "disabled" flag, so filtering is the only way to make them non-toggleable.)
- A new read-only `services/tools status` subcommand absorbs the table-printing behavior that `list` had before.
- Confirmations (e.g. inside `reset`) move to `huh.Confirm`. The plain stdin Y/n path remains as a non-TTY fallback only.

All huh widgets share the project palette through `devbox/styles.yml`. huh v2's `WithTheme` accepts a `huh.Theme` interface defined as `interface { Theme(isDark bool) *Styles }`. `huh.ThemeBase(isDark bool) *Styles` returns the default styles for either light or dark backgrounds. We implement a tiny `paletteTheme` whose `Theme(isDark bool)` method calls `huh.ThemeBase(isDark)`, applies the project palette to the returned `*huh.Styles`, and returns it. (Alternative: `huh.ThemeFunc(func(bool) *Styles)` if huh exposes that helper in v2.0.3 — pick whichever is simpler at implementation time.) No new YAML keys are introduced.

The work happens in the **separate** `devbox-cli` git repository (gitignored under `devbox-cli/` in this repo). Each task corresponds to one commit there.

## Context (from discovery)

Files/components involved:

- `devbox-cli/go.mod` — currently depends on `charm.land/bubbletea/v2 v2.0.5` and `charm.land/lipgloss/v2 v2.0.3`; needs `huh` v2.0.3 added.
- `devbox-cli/internal/ui/selector.go` — bubbletea single-pick selector (`selectorModel`, `RunSelector`, `SelectorItem`, `ErrCancelled`).
- `devbox-cli/internal/ui/selector_test.go` — tests for that selector.
- `devbox-cli/internal/ui/styles.go` — builds package-level Lipgloss style vars from `StylesConfig`; needs to additionally build a `huh.Theme`.
- `devbox-cli/internal/config/styles.go` — `StylesConfig` / `StylesColors` (no schema change in this plan).
- `devbox-cli/internal/command/service.go` — `services` command: `list`, `enable`, `disable`; calls `defaultSelectToggle` (= `ui.RunSelector`).
- `devbox-cli/internal/command/tools.go` — same pattern for tools.
- `devbox-cli/internal/command/services.go` — small helpers (`buildServiceRows`, `buildToolRows`, `sortedKeys`).
- `devbox-cli/internal/render/output.go` — `Writer.Confirm` (line-based stdin Y/n).
- `devbox-cli/internal/builtin/confirm.go` — uses `ctx.Output.Confirm`; called from deploy/reset pipelines.
- `devbox-cli/internal/commands/runner_workflow.go` — `runConfirm` for declarative workflows.
- `devbox-cli/internal/command/print.go` — `devbox print confirm` (Make-macro compatibility).
- Tests touching all the above (`*_test.go`).
- `CLAUDE.md` (root) — needs a Phase 7 entry plus updated descriptions of the `internal/ui` package and dependency list.

Related patterns found:

- Existing single-select integration shows that `defaultSelectToggle` is a typed function var so call sites can inject a fake — keep that injection pattern for the new huh-backed primitives.
- `internal/ui/styles.go` → `ApplyStyles(*config.StylesConfig)` is the single place where Lipgloss colors are rebuilt — extend it to also rebuild the `huh.Theme`.
- `containerCheckFn` in `service.go` and the `selectToggleFn` typedef show the project's preferred indirection: pass a function to commands so tests inject fakes without touching globals.

Dependencies identified:

- `charm.land/huh/v2` v2.0.3 — module path matches the project's existing `charm.land/bubbletea/v2` and `charm.land/lipgloss/v2`. Do **not** `go get` `github.com/charmbracelet/huh*` — that would pull a different module.
- `github.com/charmbracelet/x/term` is already vendored — reused for TTY detection.
- Once `RunSelector` switches to huh internally, the direct dependency on `charm.land/bubbletea/v2` may remain only as a transitive of huh; verify with `go mod tidy` before deciding to remove the explicit `require` line.

## Development Approach

- **Testing approach**: TDD where pure logic is involved (selection diffs, theme building, fallback decisions); for the huh-driven UI itself we cover behavior through small interfaces (fake selector / multi-selector / confirm functions) rather than driving real bubbletea programs.
- Complete each task fully before moving to the next.
- Make small, focused changes — each task = one `devbox-cli` commit.
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
  - tests are not optional - they are a required part of the checklist
  - write unit tests for new functions/methods
  - write unit tests for modified functions/methods
  - add new test cases for new code paths
  - update existing test cases if behavior changes
  - tests cover both success and error scenarios
- **CRITICAL: all tests must pass before starting next task** - no exceptions
- **CRITICAL: update this plan file when scope changes during implementation**
- Run `cd devbox-cli && make test && make lint` after each change.
- Maintain backward compatibility for non-TTY callers (CI, scripted deploys): `list` falls back to the table, `confirm` falls back to stdin Y/n.

## Testing Strategy

- **Unit tests**: required for every task.
  - Theme construction: `StylesColors{}` fixtures → expected `huh.Theme` field colors.
  - Selection diffing: given a preselected set and a new set, expected enable/disable lists.
  - Non-TTY fallback decision: fake `isTerminal` → table or stdin path chosen.
  - Existing tests for `service`/`tools enable|disable|status` pass with injected fakes.
- **E2E / TUI tests**: project has no Playwright/Cypress harness. Manual TTY smoke testing is captured in Post-Completion. Do **not** introduce `teatest` for huh forms in this plan.

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix.
- Document issues/blockers with ⚠️ prefix.
- Update plan if implementation deviates from original scope.
- Keep plan in sync with actual work done.

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): code changes, tests, doc updates inside this repo and the `devbox-cli/` repo.
- **Post-Completion** (no checkboxes): manual TTY smoke tests across iTerm/Ghostty, visual regression checks, and any consumer-side updates.
- **Checkbox placement**: only in `### Task N:` sections.

## Implementation Steps

### Task 1: Add huh dependency and build a huh.Theme from styles.yml
- [x] in `devbox-cli/`: run `go get charm.land/huh/v2@v2.0.3`; commit `go.mod`/`go.sum`. (Module path is `charm.land/huh/v2`, matching the existing `charm.land/bubbletea/v2` / `charm.land/lipgloss/v2` deps.)
- [x] add `devbox-cli/internal/ui/huh.go`:
  - package-level `huhTheme huh.Theme` (interface value) and `Theme() huh.Theme` accessor used at every form call site as `.WithTheme(Theme())`
  - implement a small `paletteTheme struct { colors config.StylesColors }` (or a closure) that satisfies the v2 `huh.Theme` interface: `Theme(isDark bool) *huh.Styles`. Inside the method, call `huh.ThemeBase(isDark)` to get the appropriate base `*huh.Styles`, mutate it with the project palette, and return it. **Do not cache** the returned `*Styles` across `isDark` values — huh may call `Theme(true)` and `Theme(false)` separately. Caching per `isDark` value is fine if profiling shows it matters; otherwise rebuild on each call.
  - if huh v2.0.3 exposes a `huh.ThemeFunc(fn func(bool) *Styles) Theme` helper, prefer it over a named struct (smaller surface, no caching question)
- [x] add `buildPaletteApplier(cfg *config.StylesColors) func(*huh.Styles)`:
  - returns a function that applies project palette colors (focused / blurred / selected / cursor / title / description / help / error subgroups) to a `*huh.Styles` in place. Use `styleSectionTitle`, `styleKey`, `styleMuted`, `styleEnabled`, `styleDisabled`, `styleWarn`, `styleInfoText` as the source of truth.
  - `paletteTheme.Theme(isDark)` does: `s := huh.ThemeBase(isDark); apply(s); return s`
- [x] extend `ApplyStyles` in `devbox-cli/internal/ui/styles.go` to also rebuild `huhTheme` from `cfg`; ensure default (nil cfg) yields a non-nil theme equivalent to a `paletteTheme` whose applier is a no-op (so `Theme(isDark)` returns `huh.ThemeBase(isDark)` unchanged)
- [x] write tests `devbox-cli/internal/ui/huh_test.go`:
  - `Theme()` returns non-nil before and after `ApplyStyles(nil)`
  - calling `Theme().Theme(false)` and `Theme().Theme(true)` returns non-nil `*huh.Styles` for both modes
  - `ApplyStyles` with a fixture `StylesConfig` produces a theme whose `Theme(false)` (light) carries the configured `section_title` color on whichever subgroup field most reliably reflects the palette in huh v2.0.3 (e.g. `Focused.Title.GetForeground()` — confirm field names by reading the installed module source; document the chosen field in a code comment)
- [x] run `cd devbox-cli && make test && make lint` — must pass before Task 2

⚠️ Note: huh v2's exact `*huh.Styles` field layout (subgroups like `Focused`, `Blurred`, `Group`, etc.) must be inspected from the installed module — the surface differs from huh v1. If a planned palette mapping is impossible without writing a full custom `Theme` implementation, prefer extending `paletteTheme` to override only the methods that need it rather than adding YAML keys. Record the final mapping in `huh.go`.

### Task 2: Replace RunSelector internals with huh.Select
- [x] rewrite `devbox-cli/internal/ui/selector.go`:
  - keep public surface: `SelectorItem`, `ErrCancelled`, `RunSelector(title string, items []SelectorItem) (int, error)`
  - **remove the `Disabled bool` field from `SelectorItem`** — verified by grep: no production caller sets it (only old selector tests). huh v2 `huh.NewOption` exposes only `Selected` and `String`, so there is no per-option disable to map onto. Removing the field eliminates the impossible mapping and shrinks the public surface.
  - implement via `huh.NewSelect[int]().Options(...).Title(title).WithTheme(Theme()).Value(&idx).Run()`, where each option's value is the original index in `items`. The selected `idx` is returned directly to satisfy the existing index-returning contract.
  - map `SelectorItem.Status` (`"enabled"`/`"disabled"`/free text) onto the option's description text using the existing icon mapping (✓ for "enabled", ○ for "disabled", literal text otherwise)
  - empty `items` → return `(-1, fmt.Errorf("selector: no items to display"))` (preserve the current error from `selector.go:162`)
  - return `ErrCancelled` on Esc/Ctrl-C (huh returns `huh.ErrUserAborted` — translate; also accept `tea.ErrInterrupted` if it surfaces)
- [x] delete the now-unused `selectorModel`, `prevSelectable`, `nextSelectable`, `initialCursor`, and the bubbletea-specific style vars (`styleSelectorAccent` etc.)
- [x] adjust `devbox-cli/internal/ui/selector_test.go`:
  - drop tests that pin bubbletea behavior (cursor wrap, key handling on the model, `Disabled`-aware tests at lines 146-187, 255-273)
  - keep tests that exercise the public `RunSelector` contract via an exported test hook (see "test hook visibility" below)
  - verify mapping of `SelectorItem` → option label/description and `huh.ErrUserAborted` → `ErrCancelled`
- [x] run `go mod tidy` in `devbox-cli/`; if `charm.land/bubbletea/v2` is no longer a direct dep, remove the explicit `require` line; otherwise leave it
- [x] verify `service.go`, `tools.go`, `command_cmd.go`, `shell.go` still compile and their existing tests pass
- [x] `cd devbox-cli && make test && make lint` — must pass before Task 3

### Task 3: Add a MultiSelect primitive in internal/ui
- [x] add `devbox-cli/internal/ui/multiselect.go`:
  - `type MultiSelectItem struct { Key string; Label string; Description string; Locked bool; Selected bool }`
  - `type MultiSelectResult struct { Kept []string; Locked []string }` — caller decides what to render
  - `RunMultiSelect(title string, items []MultiSelectItem) (MultiSelectResult, error)` — pure data return, **no I/O side effects in this package**. `Kept` is the keys the user left checked; `Locked` is the keys of all locked items (always present, regardless of the form). `ErrCancelled` on user abort.
  - **Locked-item strategy** (huh v2 has no per-`Option` disabled flag — verified from the v2 API: `huh.NewOption` exposes only `Selected` and `String`):
    1. Partition input into `locked` and `toggleable` slices, preserving order
    2. If `len(toggleable) == 0` — skip the form, return `MultiSelectResult{Kept: nil, Locked: locked-keys}` so the caller can decide what to print
    3. Otherwise build huh options only from `toggleable`, pre-check those with `Selected: true`
    4. Run the form; on success return `MultiSelectResult{Kept: form-result, Locked: locked-keys}`
    5. On `huh.ErrUserAborted` (or context cancellation), return zero-value result and `ErrCancelled`
  - implementation via `huh.NewMultiSelect[string]().Options(...).Title(title).Value(&keys).WithTheme(Theme()).Run()`
- [x] inside `internal/ui`: add unexported `runMultiSelectFn` for `internal/ui`'s own tests to swap; expose an unexported helper `partitionMultiSelect(items) (locked, toggleable []MultiSelectItem)` for direct testing. **Cross-package fakes follow the wrapper-var pattern documented in "Test hook visibility" — `internal/command` will hold its own `runMultiSelect = ui.RunMultiSelect` so its tests can swap that local var.**
- [x] **command-side responsibility**: `services list` / `tools list` (Tasks 5–6) print the "Always on: ..." header line themselves using `render.Stdout()` and `ui.StyleMuted` / `ui.StyleSubheader`, based on `result.Locked`. `internal/ui` stays I/O-free at this primitive's level.
- [x] write tests `devbox-cli/internal/ui/multiselect_test.go`:
  - `partitionMultiSelect` keeps order within each partition
  - building options from `toggleable` preserves order and pre-checks `Selected: true` items
  - `result.Locked` is always populated regardless of the toggleable selection (drive `RunMultiSelect` via injected fake `runMultiSelectFn`)
  - "all locked" short-circuit returns `MultiSelectResult{Locked: ..., Kept: nil}` without calling the form
  - aborting (fake returns `ErrCancelled`) propagates `ErrCancelled` and returns the zero-value result
  - tests assert no writes to any `io.Writer` (the primitive does no printing)
- [x] `cd devbox-cli && make test && make lint` — must pass before Task 4

### Task 4: Add `services status` and `tools status` subcommands
- [x] in `devbox-cli/internal/command/service.go`: add `newServiceStatusCmd(flags)` that wires the existing `runServiceList` table renderer; register it via `cmd.AddCommand` in `newServiceCmd`
- [x] in `devbox-cli/internal/command/tools.go`: add `newToolStatusCmd(flags)` that wires `runToolList`; register in `newToolCmd`
- [x] update `Long`/`Example` strings of the parent `services` / `tools` commands to mention `status`
- [x] keep `list` behavior unchanged in this task — repurposing happens in Tasks 5–6
- [x] write tests:
  - `devbox-cli/internal/command/services_test.go`: `services status` prints the same output `services list` currently produces (use existing test helpers for the table)
  - `devbox-cli/internal/command/tools_test.go`: same for `tools status`
- [x] `cd devbox-cli && make test && make lint` — must pass before Task 5

### Task 5: Repurpose `services list` as interactive multi-toggle
- [x] add `devbox-cli/internal/command/service_toggle.go` (new file) with the pure logic:
  - `func diffServiceSelection(rows []serviceRow, kept []string) (toEnable, toDisable []string)` — given current rows and the keys returned by the multi-select, compute lists, ignoring mandatory rows
  - reuse `ui.IsInteractiveFn(cmd.InOrStdin())` for the TTY check (the multi-select form needs both interactive stdin and stdout, same as confirm)
  - **add an unexported package-level wrapper** `var runMultiSelect = ui.RunMultiSelect` so `internal/command/*_test.go` files can swap in fakes (cross-package fakes can't reach `internal/ui`'s unexported vars). All call sites in `service.go` / `tools.go` use `runMultiSelect(...)` instead of `ui.RunMultiSelect(...)` directly.
- [x] rewrite the `RunE` of `newServiceListCmd`:
  - if `!ui.IsInteractiveFn(cmd.InOrStdin())` → call `runServiceList` (table) — non-TTY fallback (decision recorded). This also covers piped stdin: `devbox services list < /dev/null` prints the table and exits without entering the form.
  - else: build `[]ui.MultiSelectItem` from `buildServiceRows(cfg)` with `Locked: row.Mandatory`, `Selected: row.Enabled` (mandatory items have `Locked: true` so `Selected` is irrelevant — they are filtered out of the form by `RunMultiSelect`), `Description: row.Container`
  - **before** invoking the form, if `result.Locked` would be non-empty (i.e. there are mandatory services), print the "Always on: nginx, db, redis" header line using `render.Stdout()` + `ui.StyleSubheader("Always on: ")` + `ui.StyleMuted(strings.Join(lockedKeys, ", "))`. (Compute the locked keys via `partitionMultiSelect` exposed from `ui`, or just by filtering the rows here.)
  - call `result, err := ui.RunMultiSelect("Toggle services:", items)`; on `ErrCancelled` exit cleanly with no changes
  - `result.Kept` is the toggleable subset the user left checked; mandatory rows are not in `Kept` — they are reported back via `result.Locked` for the header but are never inputs to the diff. `diffServiceSelection(rows, result.Kept)` filters mandatory rows defensively.
  - call `diffServiceSelection`, then for each name call `setServiceEnabledNoRegen(...)`; print a one-line summary (e.g. `enabled: a, b; disabled: c`) via `render.Stdout()`; finally call `regenEnv` once
  - regenerate `.env` once at the end (currently `setServiceEnabled` calls `regenEnv` per change — refactor to skip the per-call regen and do it once after the batch; keep `setServiceEnabled` semantically intact for `enable`/`disable` callers via an optional flag like `setServiceEnabled(... , skipRegen bool)`)
- [x] update `Long`/`Example` strings of `services list` to describe the new interactive behavior; mention non-TTY fallback prints the table
- [x] write tests `devbox-cli/internal/command/service_toggle_test.go`:
  - `diffServiceSelection` table-driven cases: nothing changed; one enabled; one disabled; mandatory included in `kept` is a no-op; mandatory missing from `kept` is also a no-op (never disabled)
  - command-level test swapping the package-local `runMultiSelect` wrapper var (and overriding `ui.IsInteractiveFn`) to verify enable/disable side effects on a temp `local.yml`
  - non-TTY test: `ui.IsInteractiveFn` returns false → prints the table, no writes to `local.yml`
- [x] `cd devbox-cli && make test && make lint` — must pass before Task 6

### Task 6: Repurpose `tools list` as interactive multi-toggle
- [x] mirror Task 5 for tools in `devbox-cli/internal/command/tool_toggle.go`:
  - `diffToolSelection(rows []toolRow, kept []string) (toEnable, toDisable []string)` — tools have no mandatory concept, simpler diff
  - rewrite `newToolListCmd.RunE` using `ui.IsInteractiveFn(cmd.InOrStdin())` for the TTY/non-TTY split
  - batch `setToolEnabled` calls; regenerate `.env` once at the end (refactor `setToolEnabled` like `setServiceEnabled`)
- [x] update `Long`/`Example` of `tools list`
- [x] write tests `devbox-cli/internal/command/tool_toggle_test.go`:
  - `diffToolSelection` table-driven cases
  - command-level test swapping the package-local `runMultiSelect` wrapper + override of `ui.IsInteractiveFn`
  - non-TTY fallback prints the table
- [x] `cd devbox-cli && make test && make lint` — must pass before Task 7

### Task 7: Replace confirmations with huh.NewConfirm
- [ ] **plumb stdin through the contexts** (prerequisite for clean fallback testing):
  - `devbox-cli/internal/builtin/builtin.go`: add `Stdin io.Reader` to `ExecContext` (default `os.Stdin` at the call site if nil)
  - `devbox-cli/internal/commands/runner.go`: add `Stdin io.Reader` to `RunContext` (default `os.Stdin` at the runner entry point if nil)
  - update every place that constructs an `ExecContext` or `RunContext` to pass stdin (deploy/reset pipelines, command runner, tests). Most call sites can simply assign `os.Stdin`; tests will pass `bytes.NewBufferString("y\n")` etc.
- [ ] add `devbox-cli/internal/ui/confirm.go`:
  - `RunConfirm(title, affirmative, negative string) (bool, error)` — returns the user's choice; `ErrCancelled` on Esc/Ctrl-C
  - unexported `runConfirmFn` for `internal/ui`'s own tests; cross-package fakes use the wrapper-var pattern (each consumer package adds its own `var runConfirm = ui.RunConfirm`)
  - small interactivity helper exported for reuse from `builtin` and `commands`:
    ```go
    var IsInteractiveFn = func(stdin io.Reader) bool {
        // huh needs both: a TTY stdin to read keypresses AND a TTY stdout to render.
        // If stdin came from a pipe (echo y | devbox ...), we MUST use the line-based fallback.
        if !term.IsTerminal(os.Stdout.Fd()) { return false }
        f, ok := stdin.(*os.File)
        if !ok { return false } // tests pass bytes.Buffer etc — never interactive
        return term.IsTerminal(f.Fd())
    }
    ```
    Defined once in `ui`; callers pass `ctx.Stdin` (or `cmd.InOrStdin()`) so a piped stdin correctly routes to the stdin Y/n fallback.
- [ ] update `devbox-cli/internal/builtin/confirm.go`:
  - add unexported wrapper `var runConfirm = ui.RunConfirm` at package scope so tests in `internal/builtin` can swap it
  - if `ctx.SkipConfirm` → no-op (unchanged)
  - if `ctx.ConfirmFunc != nil` → use the injected callback (unchanged — tests rely on this)
  - else if `ui.IsInteractiveFn(ctx.Stdin)` → call `runConfirm(msg, okMsg, stopMsg)`
  - else → fall back to `ctx.Output.Confirm(msg, ctx.Stdin)` (replace the current `os.Stdin` literal with `ctx.Stdin`; if nil, default to `os.Stdin` inside `Run`). `ctx.Output` is `*render.Writer` (already a field on `ExecContext`) so this path stays as-is.
- [ ] update `devbox-cli/internal/commands/runner_workflow.go::runConfirm`:
  - **`RunContext` does not have an `Output` field** (verified — `runner.go` only has `Stdout io.Writer` and `Stderr io.Writer`). The current implementation uses `bufio.NewScanner(os.Stdin)` directly with custom `[y/N]` logic and prints via `stdout(ctx)`.
  - replace direct `os.Stdin` usage with `ctx.Stdin` (default to `os.Stdin` if nil)
  - add unexported wrapper `var runConfirm = ui.RunConfirm` at package scope for test injection
  - branch:
    - keep the existing `isNonInteractive()` (DEVBOX_NONINTERACTIVE=1) auto-confirm gate unchanged
    - else if `ui.IsInteractiveFn(ctx.Stdin)` → call `runConfirm(message, "Yes", "No")` and return error if it returned false (the workflow's existing semantics: false = abort with error)
    - else → use the existing `bufio.Scanner` over `ctx.Stdin` (or wrap it via `render.NewWriter(stdout(ctx)).Confirm(message, ctx.Stdin)` if you want to consolidate on `render.Writer.Confirm` for consistency with the builtin path; pick one and document the choice)
  - the existing `step.Confirm` is just a `string` message, so map it as `runConfirm(message, "Yes", "No")` — the affirmative/negative labels are static here
- [ ] update `devbox-cli/internal/command/print.go::Confirm` (the `devbox print confirm` subcommand):
  - the `command` package already declares `runConfirm = ui.RunConfirm` (added during Task 5/6 if needed; otherwise add it here)
  - branch the same way: `ui.IsInteractiveFn(cmd.InOrStdin())` → call `runConfirm(message, "Yes", "No")`; else `render.Stdout().Confirm(message, cmd.InOrStdin())` (replace the current `os.Stdin` literal at `print.go:101`)
- [ ] keep `render.Writer.Confirm` — it stays as the documented non-TTY fallback. Add a one-line Go doc comment recording that intent.
- [ ] write tests:
  - `confirm_test.go` (builtin): four paths —
    1. `ConfirmFunc` injected (existing test, still passes)
    2. TTY: swap the package-local `runConfirm` wrapper with a fake returning true/false; verify return value and error
    3. non-TTY: `ui.IsInteractiveFn` overridden to return false, `ctx.Stdin = bytes.NewBufferString("y\n")` (and `"n\n"`) — verify `ctx.Output.Confirm` is exercised and result is correct
    4. piped-stdin-but-tty-stdout: `ui.IsInteractiveFn` returns false because stdin is a `bytes.Buffer` (not a TTY) — covers the `echo y | devbox reset run` case from the smoke checklist
  - `runner_workflow_test.go`: cover both TTY and non-TTY branches by swapping the package-local `runConfirm` wrapper and injecting `RunContext.Stdin`
  - `print_test.go`: cover both branches by swapping the `command` package's `runConfirm` wrapper and using `cmd.SetIn(...)`
- [ ] `cd devbox-cli && make test && make lint` — must pass before Task 8

### Task 8: Remove dead code and tighten imports
- [ ] grep `devbox-cli/` for `selectorModel`, `prevSelectable`, `nextSelectable`, `initialCursor`, `styleSelectorAccent`, `styleSelectorMuted`, `styleSelectorEnabled`, `styleSelectorHint` — must be 0 results
- [ ] run `go mod tidy` and verify the `require` block is minimal; if `charm.land/bubbletea/v2` is now only transitive, drop the explicit line and leave it in the indirect block
- [ ] confirm `internal/ui` no longer imports `charm.land/bubbletea/v2` directly
- [ ] re-verify the existing test suite still passes (no test file touches removed symbols)
- [ ] `cd devbox-cli && make test && make lint`

### Task 9: Documentation and reference regeneration
- [ ] update root `CLAUDE.md`:
  - add Phase 7 entry under "Migration phases" describing huh integration
  - add `charm.land/huh/v2` to the dependency list under "devbox-cli → Dependencies"
  - update the `internal/ui` description to list `RunSelector`, `RunMultiSelect`, `RunConfirm` (huh-backed) and `Theme()` accessor
  - update the `services` / `tools` command bullets to mention `status` and the new interactive `list`
  - reflect that `render.Writer.Confirm` is now a non-TTY fallback only
- [ ] **rebuild the binary first**: `cd devbox-cli && make build` — produces `../bin/devbox` reflecting the new commands (`status`) and updated `Long`/`Example` text. Without this step `docs generate` would emit reference for the previous binary.
- [ ] regenerate CLI reference: `./bin/devbox docs generate` (run from repo root)
- [ ] inspect diff of `docs/reference/cli/devbox_services*.md` and `docs/reference/cli/devbox_tools*.md` (note: filenames are `devbox_*` prefixed, matching cobra's default naming — verified against the existing files in `docs/reference/cli/`); commit the regenerated files
- [ ] no test changes expected — running `make test && make lint` must still pass

### Task 10: Verify acceptance criteria
- [ ] verify all four user goals from Overview are met (Select for enable/disable, status subcommand, MultiSelect for list, Confirm for confirmations)
- [ ] verify mandatory services cannot be toggled off via the multi-select
- [ ] run full test suite: `cd devbox-cli && make test`
- [ ] run linter: `cd devbox-cli && make lint` — all issues fixed
- [ ] verify huh widgets pick up `devbox/styles.yml` palette by changing `colors.section_title` in `styles.yml` and observing the change in a manual smoke run (record screenshot path in Post-Completion if useful)
- [ ] verify build artifact: `cd devbox-cli && make build` produces `../bin/devbox`
- [ ] verify coverage on changed packages with `go test -cover ./internal/ui/... ./internal/command/... ./internal/builtin/...` meets project standard (80%+); add cases if short

## Technical Details

### huh.Theme mapping (Task 1)

`huh.Theme` in v2 is an interface: `interface { Theme(isDark bool) *Styles }`. `huh.ThemeBase(isDark bool)` returns the default `*huh.Styles` for the given mode. The plan implements a tiny `paletteTheme` whose `Theme(isDark bool)` method calls `huh.ThemeBase(isDark)`, applies the project palette to the returned `*Styles`, and returns it. (If `huh.ThemeFunc` exists in v2.0.3, use it instead of a named struct.)

Source palette (`StylesColors`) → target subgroup on the returned `*huh.Styles`. Exact field names must be confirmed against the installed `charm.land/huh/v2 v2.0.3` source (read it during Task 1 implementation); this table is the **intent**, not a verified mapping:

| StylesColors field | `*huh.Styles` subgroup intent                           |
|--------------------|---------------------------------------------------------|
| `section_title`    | focused title / form title                              |
| `label`            | focused selected option / cursor                        |
| `subheader`        | focused description                                     |
| `muted`            | blurred / unselected option text, help text             |
| `enabled`          | selected/checked indicator (multi-select)               |
| `disabled`         | inactive option foreground                              |
| `warning`          | error / aborted message                                 |
| `info`             | informational hint line                                 |
| `mandatory`        | (locked items are rendered outside the form, not by huh styles — see Task 3 strategy) |

If huh v2.0.3 exposes fewer subgroups than expected, prefer mapping `section_title` → form title and `label` → focused selection; document any unmapped palette entries inline in `huh.go`.

### Selection diff (Tasks 5, 6)

```go
// rows: current state, kept: keys returned by huh.MultiSelect (set of names left checked).
// Mandatory rows are never enabled/disabled here — they are filtered before diffing.
toEnable  = { row.Name | row in rows, !row.Mandatory, !row.Enabled,  row.Name in kept }
toDisable = { row.Name | row in rows, !row.Mandatory,  row.Enabled, row.Name not in kept }
```

For tools the mandatory filter is unconditionally false.

### Setter refactor (Tasks 5, 6)

`setServiceEnabled` and `setToolEnabled` currently call `regenEnv` per invocation. Add an internal variant (e.g. `setServiceEnabledNoRegen`) that the multi-toggle path calls in a loop, then runs `regenEnv` once. The existing `enable`/`disable` commands keep their current single-call semantics.

### TTY detection

Use `github.com/charmbracelet/x/term` (already vendored). The exported `ui.IsInteractiveFn(stdin io.Reader) bool` helper checks **both** that stdout is a TTY and that the supplied stdin is a `*os.File` referring to a TTY. This is essential: without the stdin check, `echo y | devbox reset run` (TTY stdout, piped stdin) would incorrectly enter the huh form and hang or misread input. The helper is overridable from tests in `builtin` and `commands` packages.

### Test hook visibility (cross-package fakes)

Go does not let other packages reach into a package's unexported vars. Each `internal/ui` primitive (`RunSelector`, `RunMultiSelect`, `RunConfirm`) is an exported function — but tests in `internal/command`, `internal/builtin`, `internal/commands` need to inject fakes without driving real huh forms.

**Pattern: each consumer package owns its own swap-var pointing at the `ui` primitive.** This mirrors the existing `defaultSelectToggle = ui.RunSelector` in `internal/command/service.go`, which already works.

For each primitive, the wrapper var lives in the consumer package:

| Primitive          | Consumer package      | Wrapper var (unexported, package-local)        |
|--------------------|-----------------------|------------------------------------------------|
| `ui.RunSelector`   | `internal/command`    | `defaultSelectToggle` (already exists)         |
| `ui.RunMultiSelect`| `internal/command`    | `runMultiSelect = ui.RunMultiSelect`           |
| `ui.RunConfirm`    | `internal/builtin`    | `runConfirm = ui.RunConfirm`                   |
| `ui.RunConfirm`    | `internal/commands`   | `runConfirm = ui.RunConfirm`                   |
| `ui.RunConfirm`    | `internal/command`    | `runConfirm = ui.RunConfirm` (for `print.go`)  |
| `ui.IsInteractiveFn` | `internal/ui`        | exported (var assignment) — overridable from any package |

Each wrapper var is unexported but lives in the same package as the test file that swaps it, so the test can do `t.Cleanup(func(){ runMultiSelect = ui.RunMultiSelect }); runMultiSelect = fakeFn`. Tests in `internal/ui` itself test the primitive directly via its own package-local `runMultiSelectFn` (which can be unexported because the tests live in `internal/ui`).

This keeps the public API of `internal/ui` minimal: the primitives stay exported, but the test-injection points are owned by each consumer.

### Stdin plumbing

`ExecContext` (deploy/reset builtins) and `RunContext` (declarative command runner) both gain an `Stdin io.Reader` field. Construction sites default to `os.Stdin` when nil; tests inject `bytes.NewBufferString(...)`. This removes the current direct `os.Stdin` reference inside `builtin/confirm.go` and `runner_workflow.go`, which is what makes the non-TTY confirm path testable without global swapping.

### Confirmation routing

```
SkipConfirm                    → no-op
ConfirmFunc                    → injected (tests)
IsInteractiveFn(ctx.Stdin)     → ui.RunConfirm  (huh — both stdin AND stdout are TTYs)
otherwise (piped stdin or no TTY) → ctx.Output.Confirm(msg, ctx.Stdin)  (stdin Y/n)
```

## Post-Completion

*Items requiring manual intervention or external systems — no checkboxes, informational only.*

**Manual verification:**
- Smoke test on a real terminal (iTerm2 / Ghostty / Alacritty):
  - `devbox services list` — multi-select shows mandatory services as locked, non-mandatory pre-checked according to current state
  - toggle one tool on, one off, submit → `.env` regenerated once, `local.yml` reflects both changes
  - `devbox services enable` / `devbox tools disable` with no arg → huh.Select opens with the right candidate set
  - cancel each form with Esc / Ctrl-C → no writes, exit code 0
  - run `devbox reset run` and answer the confirm prompt with both Y and N — verify abort path
- Non-TTY checks:
  - `devbox services list | cat` — prints the table, makes no changes
  - `echo y | devbox reset run` — proceeds via stdin fallback
  - `echo n | devbox reset run` — aborts via stdin fallback
- Visual palette check: change `colors.section_title` in `devbox/styles.yml` and re-run any huh form; the title color should follow.

**External system updates:**
- None — `devbox-cli` is consumed only by this repo's Make facade; no downstream consumers to update.
- After all tasks land, push the corresponding commits in the `devbox-cli` repo and tag a new build if release tagging is used there.
