# Shell Interactive Mode

## Overview
- Evolve `devbox shell` into the unified interactive entrypoint for service containers
- Add `--mode auto|exec|run`, `--shell`, `--user`, `--workdir` flags with config-driven defaults
- Extend `ServiceCLIConfig` with `Mode` and `Env` fields
- Add bubbletea-based interactive selectors across CLI:
  - `devbox shell` — service selector when multiple services exist
  - `services enable/disable` — service picker with enabled/disabled state indicators
  - `tools enable/disable` — tool picker with enabled/disabled state indicators
  - `commands run/inspect` — command picker; group prefix narrows the list
- Infrastructure consoles (db.cli, redis.cli) are out of scope — separate follow-up plan

## Context (from discovery)
- Files involved:
  - `devbox-cli/internal/command/shell.go` — shell command definition, flags
  - `devbox-cli/internal/command/service_cli.go` — container state detection, exec/run logic
  - `devbox-cli/internal/command/service.go` — services list/enable/disable (currently `ExactArgs(1)`)
  - `devbox-cli/internal/command/tools.go` — tools list/enable/disable (currently `ExactArgs(1)`, `knownTools` map)
  - `devbox-cli/internal/command/command_cmd.go` — commands list/inspect/run (currently `ExactArgs(1)` for run/inspect)
  - `devbox-cli/internal/commands/registry.go` — `Registry`, `GroupNode` tree, `List()`/`ListAll()` with group prefix filter
  - `devbox-cli/internal/config/devbox.go` — `ServiceConfig`, `ServiceCLIConfig` structs
  - `devbox/services.yml` — service definitions with `cli` block
  - `devbox-cli/internal/command/shell_status_version_test.go` — existing tests
  - `devbox-cli/internal/config/devbox_test.go` — config tests
- Current state: shell already has `--root` flag, auto-detects container state, resolves shell/user/workdir from `ServiceCLIConfig`
- `ServiceCLIConfig` currently has `Shell`, `User`, `WorkDir` — needs `Mode` and `Env`
- bubbletea/bubbles are NOT yet dependencies (lipgloss v2 and fang v2 are already present from charmbracelet ecosystem)
- services enable/disable, tools enable/disable, commands run/inspect all require exact positional arg — no interactive fallback
- Command registry supports `List(groupPrefix)` which filters commands by dot-prefix (e.g. `"services.main"` returns all `services.main.*` commands)

## Repository & Branching
- `devbox-cli/` is a **separate git repository** (submodule/nested repo), not part of the `next-laravel` repo
- **Create a feature branch** in `devbox-cli/` before starting (e.g. `feature/shell-interactive-mode`)
- **Commit after each completed task** in `devbox-cli/` — small, focused commits
- **Commit after code review fixes** — do not amend, create new commits so review history is preserved
- Changes to `next-laravel` repo files (`devbox/services.yml`, `docs/plans/`, `CLAUDE.md`) are committed separately in the outer repo on its own branch

## Development Approach
- **Testing approach**: Regular (code first, then tests)
- Complete each task fully before moving to the next
- Make small, focused changes
- **CRITICAL: every task MUST include new/updated tests**
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- Run tests after each change
- Maintain backward compatibility

## Testing Strategy
- **Unit tests**: required for every task
- Config parsing tests for new `Mode`/`Env` fields
- Flag validation tests (`--root` + `--user` mutual exclusion, `--mode` values)
- Service resolution tests (mode logic: auto/exec/run)
- Interactive selector model tested via bubbletea msg/update pattern (no real terminal needed)
- Enable/disable interactive flow tested by checking arg-optional behavior and fallback to selector

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Update plan if implementation deviates from original scope

## Implementation Steps

### Task 1: Extend ServiceCLIConfig with Mode and Env
- [x] Add `Mode string` field to `ServiceCLIConfig` in `devbox-cli/internal/config/devbox.go` (yaml tag: `mode`)
- [x] Add `Env map[string]string` field to `ServiceCLIConfig` (yaml tag: `env`)
- [x] Update `LoadServicesConfig` extends resolution to inherit `Mode` and `Env` from parent
- [x] Update `services.yml` — add `mode: auto` to `main` service's `cli` block
- [x] Write tests for config loading with new fields (mode, env, extends inheritance)
- [x] Run tests — must pass before next task

### Task 2: Add CLI flags to shell command
- [ ] Add `--mode` string flag (default: empty, values: `auto`, `exec`, `run`) to `newShellCmd`
- [ ] Add `--shell` string flag (default: empty) to `newShellCmd`
- [ ] Add `--user` string flag (default: empty) to `newShellCmd`
- [ ] Add `--workdir` string flag (default: empty) to `newShellCmd`
- [ ] Add validation: `--root` and `--user` are mutually exclusive (error if both set)
- [ ] Add validation: `--mode` must be one of `auto`, `exec`, `run` (or empty)
- [ ] Update command Long description and Example to reflect new flags
- [ ] Pass new flags to `runServicesCLI` (update function signature)
- [ ] Write tests for flag registration, mutual exclusion, mode validation
- [ ] Run tests — must pass before next task

### Task 3: Implement 3-tier value resolution (flags -> config -> defaults)
- [ ] Create `shellOptions` struct to hold resolved values: `Mode`, `Shell`, `User`, `WorkDir`, `Env`
- [ ] Create `resolveShellOptions(flags, svcCLI ServiceCLIConfig, svc ServiceConfig) shellOptions` function
- [ ] Resolution priority: CLI flag (if non-empty) -> config value -> built-in default
- [ ] Built-in defaults: mode=`auto`, shell=`bash`, user=current UID, workdir=`work_dir_internal` -> `dir_internal`
- [ ] `--root` sets user to `root` (highest priority, already handled but integrate into new flow)
- [ ] Update `runServicesCLI` to use `resolveShellOptions` instead of inline resolution
- [ ] Write tests for resolution priority (flag overrides config, config overrides default)
- [ ] Run tests — must pass before next task

### Task 4: Implement explicit mode logic
- [ ] Refactor `runServicesCLI` to use resolved `Mode` value from `shellOptions`
- [ ] `auto` mode (current behavior): running->exec, not exists->run, stopped/paused/dead->error with hint
- [ ] `exec` mode: always exec, error if container not running (`container %q is not running — start it with 'devbox up'`)
- [ ] `run` mode: always `docker compose run --rm`, regardless of container state
- [ ] Pass `Env` from `shellOptions` as `-e KEY=VALUE` args to both exec and run
- [ ] Write tests for mode logic (auto/exec/run behavior with different container states)
- [ ] Write tests for env passthrough
- [ ] Run tests — must pass before next task

### Task 5: Add bubbletea dependency and shared selector component
- [ ] Add `github.com/charmbracelet/bubbletea/v2` v2.0.5 and `github.com/charmbracelet/bubbles/v2` v2.1.0
- [ ] Create `devbox-cli/internal/ui/selector.go` — reusable interactive list selector model
- [ ] Selector model features:
  - Items are `[]SelectorItem` with `Label`, `Description`, `Status` (e.g. "enabled"/"disabled"), `Disabled` (non-selectable)
  - Arrow keys (up/down) to navigate, Enter to select, Esc/q to cancel
  - Current item highlighted with accent color (from styles palette)
  - Status shown inline: checkmark + green for enabled, dimmed for disabled
  - Returns selected item index or cancellation error
- [ ] Create `RunSelector(title string, items []SelectorItem) (int, error)` public entry point
- [ ] Write unit tests for selector model (Init, Update with key msgs, View output, cancel behavior)
- [ ] Run tests — must pass before next task

### Task 6: Interactive selector in `devbox shell`
- [ ] Change `shell.go` args from `cobra.MaximumNArgs(1)` (already) — keep current behavior
- [ ] When no service arg AND multiple enabled services: build `SelectorItem` list from enabled services (label=name, description=container)
- [ ] Call `RunSelector` and use selected service name
- [ ] When only one enabled service: auto-select (no selector, current behavior)
- [ ] When no enabled services: error
- [ ] Write tests for selection logic (single auto-select, no services error, multi triggers selector)
- [ ] Run tests — must pass before next task

### Task 7: Interactive selector in `services enable/disable`
- [ ] Change `services enable` args from `ExactArgs(1)` to `MaximumNArgs(1)` in `service.go`
- [ ] When no arg: show selector with all non-mandatory services, each showing enabled/disabled state
  - Enabled services: checkmark prefix, green/enabled color
  - Disabled services: no prefix, dimmed/disabled color
  - For `enable`: filter to show only currently disabled services (or show all with state, skip if already enabled)
  - For `disable`: filter to show only currently enabled non-mandatory services
- [ ] Change `services disable` args from `ExactArgs(1)` to `MaximumNArgs(1)` similarly
- [ ] Keep direct arg path working unchanged (backward compatible)
- [ ] Write tests for arg-optional behavior (0 args triggers selector, 1 arg works as before)
- [ ] Run tests — must pass before next task

### Task 8: Interactive selector in `tools enable/disable`
- [ ] Change `tools enable` args from `ExactArgs(1)` to `MaximumNArgs(1)` in `tools.go`
- [ ] When no arg: show selector with all tools from `knownTools`, each showing enabled/disabled state
  - Same visual treatment as services: checkmark + color for enabled, dimmed for disabled
  - For `enable`: show only disabled tools (or all with state)
  - For `disable`: show only enabled tools
- [ ] Change `tools disable` args similarly
- [ ] Keep direct arg path working unchanged
- [ ] Write tests for arg-optional behavior
- [ ] Run tests — must pass before next task

### Task 9: Interactive selector in `commands run` and `commands inspect`
- [ ] Change `commands run` args from `ExactArgs(1)` to `MaximumNArgs(1)` in `command_cmd.go`
- [ ] When no arg: show selector with all public commands from `registry.List("")`
  - Items: label=command ID, description=command description
- [ ] When arg is a group prefix (e.g. `services.main`): use `registry.List(groupPrefix)` to get commands in that group, show selector among them
  - Detect group vs command: try `registry.Get(arg)` first; if not found, try `registry.List(arg)` — if non-empty, it's a group
- [ ] When arg is a full command ID: run directly (current behavior, no selector)
- [ ] Change `commands inspect` args from `ExactArgs(1)` to `MaximumNArgs(1)` similarly
- [ ] Same group-prefix logic for inspect
- [ ] Write tests for: no arg -> full list, group prefix -> filtered list, exact ID -> direct run
- [ ] Run tests — must pass before next task

### Task 10: Verify acceptance criteria
- [ ] Verify `devbox shell main` works with all flags (`--mode`, `--shell`, `--user`, `--workdir`, `--root`)
- [ ] Verify `--root` and `--user` mutual exclusion produces clear error
- [ ] Verify 3-tier resolution: flag > config > default
- [ ] Verify `mode: exec` errors when container not running
- [ ] Verify `mode: run` always starts new container
- [ ] Verify env passthrough from config and flags
- [ ] Verify interactive selector appears for multi-service `devbox shell`
- [ ] Verify `services enable` (no arg) shows disabled services with state indicators
- [ ] Verify `services disable` (no arg) shows enabled non-mandatory services
- [ ] Verify `tools enable/disable` interactive selectors work
- [ ] Verify `commands run services.main` shows group commands interactively
- [ ] Verify `commands run` (no arg) shows all public commands
- [ ] Verify `commands inspect` interactive selection works
- [ ] Run full test suite (`cd devbox-cli && make test`)
- [ ] Run linter (`cd devbox-cli && make lint`) — all issues must be fixed
- [ ] Verify test coverage meets project standard

### Task 11: [Final] Update documentation
- [ ] Update `devbox docs generate` output (CLI reference) by verifying help text is correct
- [ ] Update CLAUDE.md: add bubbletea/bubbles to dependency list, document interactive selector pattern in `internal/ui`

## Technical Details

### Flag-to-config resolution flow
```
CLI flags (--mode, --shell, --user, --workdir, --root)
  | (non-empty overrides)
services.yml -> services.<name>.cli.{mode, shell, user, workdir, env}
  | (non-empty overrides)
Built-in defaults: mode=auto, shell=bash, user=<UID>, workdir=<work_dir_internal>
```

### Mode behavior matrix
| Mode   | Container running | Container absent | Container stopped  |
|--------|-------------------|------------------|--------------------|
| `auto` | `docker exec`     | `compose run`    | Error + hint       |
| `exec` | `docker exec`     | Error            | Error              |
| `run`  | `compose run`     | `compose run`    | `compose run`      |

### Env passthrough
- Config `env` map and flag env vars are passed as `-e KEY=VALUE` to both `docker exec` and `docker compose run`
- Flag env vars override config env vars with the same key

### ServiceCLIConfig changes
```go
type ServiceCLIConfig struct {
    Mode    string            `yaml:"mode"`    // auto|exec|run
    Shell   string            `yaml:"shell"`
    User    string            `yaml:"user"`
    WorkDir string            `yaml:"workdir"`
    Env     map[string]string `yaml:"env"`
}
```

### Selector component (`internal/ui/selector.go`)
```go
// SelectorItem represents one option in the interactive list.
type SelectorItem struct {
    Label       string // display name (e.g. "main", "adminer", "services.main.migrate")
    Description string // secondary text (e.g. "app-main", "Database admin UI")
    Status      string // state indicator: "enabled", "disabled", "" (no state)
    Disabled    bool   // if true, item is shown but not selectable
}

// RunSelector shows an interactive list and returns the selected index.
// Returns ErrCancelled if user presses Esc/q.
func RunSelector(title string, items []SelectorItem) (int, error)
```

### Interactive behavior per command

| Command | No arg | Group prefix arg | Full ID arg |
|---------|--------|------------------|-------------|
| `shell` | selector (enabled services) | n/a | direct run |
| `services enable` | selector (disabled non-mandatory) | n/a | direct enable |
| `services disable` | selector (enabled non-mandatory) | n/a | direct disable |
| `tools enable` | selector (disabled tools) | n/a | direct enable |
| `tools disable` | selector (enabled tools) | n/a | direct disable |
| `commands run` | selector (all public) | selector (group commands) | direct run |
| `commands inspect` | selector (all commands) | selector (group commands) | direct inspect |

### Dependencies
```
github.com/charmbracelet/bubbletea/v2 v2.0.5
github.com/charmbracelet/bubbles/v2   v2.1.0
```

## Post-Completion

**Follow-up plans:**
- Infrastructure console commands (db.cli, redis.cli) via declarative command system
- Sugar commands (`devbox db cli`, `devbox redis cli`) as aliases

**Manual verification:**
- Test interactive selector in real terminal (arrow keys, enter, esc, ctrl+c)
- Test with Docker Desktop running/stopped/absent containers
- Test extends inheritance (main-debug inherits main cli config + adds env)
- Test `commands run services.main` shows only services.main.* commands
- Test enable/disable selectors show correct state indicators (colors, checkmarks)
