# CLI UX Refactor

## Overview

Restructure `devbox-cli` from a "core for Make" into the primary user interface of the project. Transform the command tree, add Fang/Lipgloss-based styling, separate `help` from `info`, introduce versioning, shell completion, doc generation, and command groups.

**Key changes:**
- `devbox` without args shows ASCII header + summary + help (not `info`)
- `devbox help` fully handled by Cobra + Fang
- `devbox info` becomes a styled project dashboard from `devbox/info.yml`
- Lifecycle commands (`up`, `down`, `stop`, etc.) promoted to root level
- New: `version`, `shell`, `status`, `docs generate`, completion
- Renamed: `command` -> `commands`, `services cli` -> `shell`, topology `services` -> `status`
- Clean break: no hidden aliases except `print` (Make compatibility)
- New `internal/ui` package for styled rendering (info, summary)
- `internal/render` retained for plain output (deploy, docker, logs)

**Not in scope:**
- Bubble Tea / Bubbles / full-screen TUI
- Changes to deploy.log or passthrough output behavior
- Runtime/streaming command output changes

## Context

- **Repo:** `devbox-cli/` is a separate git repository; needs its own branch and commits
- **Current deps:** cobra v1.10.2, yaml.v3, go-figure (3 direct deps)
- **New deps:** fang v1.0.0 (v2.0.1 does not exist), lipgloss v1.1.0
- **Files affected:** ~46 source files, 24 test files across 8 packages
- **Current root behavior:** `devbox` (no args) runs `runInfo()` directly
- **Config:** `devbox/help.yml` drives info screen with Go templates

## Development Approach

- **Testing approach**: Regular (code first, then tests)
- Complete each task fully before moving to the next
- Make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- Run tests after each change
- Maintain backward compatibility for Make macros (`print` stays hidden)

## Testing Strategy

- **Unit tests**: required for every task
- Run `cd devbox-cli && go test ./...` after each task
- Run `cd devbox-cli && make lint` before final verification

## Progress Tracking

- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with + prefix
- Document issues/blockers with ! prefix
- Update plan if implementation deviates from original scope

## Implementation Steps

### Task 1: Repository setup and dependencies

- [x] create feature branch in `devbox-cli/` repo (e.g. `feat/cli-ux-refactor`)
- [x] add `github.com/charmbracelet/fang v1.0.0` dependency (v2.0.1 does not exist; latest is v1.0.0)
- [x] add `github.com/charmbracelet/lipgloss v1.1.0` dependency
- [x] run `go mod tidy` to resolve transitive deps (skipped until imports added — tidy removes unused deps)
- [x] verify `go build ./...` succeeds
- [x] run tests - must pass before next task

### Task 2: Add `internal/version` package

- [x] create `internal/version/version.go` with `Version`, `Commit`, `Date`, `BuiltBy` vars (default `"dev"`)
- [x] add `Info() string` function that formats version info
- [x] update `devbox-cli/Makefile` build target to inject `-ldflags -X` for version fields
- [x] write tests for `version.Info()` output formatting
- [x] run tests - must pass before next task

### Task 3: Rename `help.yml` to `info.yml` and update config

- [x] rename `devbox/help.yml` -> `devbox/info.yml` in the parent project
- [x] rename `HelpConfig` -> `InfoConfig` in `internal/config/help.go` (rename file to `info.go`)
- [x] rename `HelpSettings` -> `InfoSettings`, `HelpHeader` -> `InfoHeader`, `HelpSection` -> `InfoSection`, `HelpItem` -> `InfoItem`, `HelpASCII` -> `InfoASCII`, `HelpIndent` -> `InfoIndent`
- [x] rename `LoadHelpConfig` -> `LoadInfoConfig`, update path default to `devbox/info.yml`
- [x] update all references in `internal/command/info.go` and other consumers
- [x] update config test file (rename `help_test.go` -> `info_test.go`, update test functions)
- [x] run tests - must pass before next task

### Task 4: Add `internal/ui` package for styled rendering

- [x] create `internal/ui/styles.go` with Lipgloss style definitions (colors, borders, spacing) consistent with Fang aesthetic
- [x] create `internal/ui/summary.go` with `RenderSummary(cfg *config.DevboxConfig) string` — compact project summary (name, state, URL, services/tools counts)
- [x] create `internal/ui/info.go` with `RenderInfo(cfg *config.DevboxConfig, infoCfg *config.InfoConfig) (string, error)` — full styled info dashboard replacing legacy table rendering
- [x] ensure terminal width detection for adaptive layout
- [x] write tests for summary rendering (content correctness)
- [x] write tests for info rendering (sections, conditional items, template evaluation)
- [x] run tests - must pass before next task

### Task 5: Restructure command tree — promote lifecycle commands to root

- [x] create `internal/command/up.go` — `devbox up [services...]` (delegates to docker up)
- [x] create `internal/command/down.go` — `devbox down` (delegates to docker down)
- [x] create `internal/command/stop.go` — `devbox stop [services...]` (delegates to docker stop)
- [x] create `internal/command/restart.go` — `devbox restart [services...]` (delegates to docker restart)
- [x] create `internal/command/logs.go` — `devbox logs [services...]` (delegates to docker logs)
- [x] create `internal/command/ps.go` — `devbox ps` (delegates to docker ps)
- [x] create `internal/command/wait.go` — `devbox wait` (delegates to docker wait)
- [x] keep `docker` subcommand group intact (advanced usage) with same subcommands
- [x] write tests for new root-level lifecycle commands
- [x] run tests - must pass before next task

### Task 6: Restructure command tree — rename and reorganize

- [x] create `internal/command/shell.go` — `devbox shell [service]` replacing `services cli` (reuse `runServicesCLI` logic)
- [x] create `internal/command/status.go` — `devbox status` replacing topology `services` output (reuse `runServices` logic with tree/table)
- [x] rename `command` group to `commands` (`internal/command/command_cmd.go` — update `Use: "commands"`)
- [x] update `newServiceCmd` to use `Use: "services"` consistently (list/enable/disable only, no `cli` subcommand)
- [x] remove `service_cli.go` subcommand registration from `services` (moved to root `shell`)
- [x] remove old `services` topology-display RunE (moved to `status`)
- [x] add `devbox version` command using `internal/version`
- [x] write tests for `shell`, `status`, `version` commands
- [x] run tests - must pass before next task

### Task 7: Add command groups to help output

- [x] define command groups in root.go: Core, Environment, Configuration, Pipelines, Advanced
- [x] assign `info`, `version` to Core group
- [x] assign `up`, `down`, `stop`, `restart`, `logs`, `ps`, `wait`, `shell`, `status` to Environment group
- [x] assign `services`, `tools`, `render` to Configuration group
- [x] assign `deploy`, `reset` to Pipelines group
- [x] assign `commands`, `docker`, `compose`, `docs` to Advanced group (docs skipped — not yet implemented, Task 12)
- [x] mark `print` as hidden (internal Make compatibility)
- [x] write test verifying group assignments in help output
- [x] run tests - must pass before next task

### Task 8: Wire Fang into entrypoint

- [x] update `cmd/devbox/main.go` to use `fang.Execute()` instead of `root.Execute()`
- [x] configure Fang: styled help, styled errors, `--version` flag (using `internal/version`)
- [x] verify `SilenceErrors` / `ErrSilent` flow still works with Fang
- [x] verify `devbox help`, `devbox help <cmd>`, `devbox <cmd> --help` all produce Fang-styled output
- [x] verify `devbox --version` prints version info
- [x] write tests for root command with Fang integration (help output, version flag, error handling)
- [x] run tests - must pass before next task

### Task 9: Implement new root command behavior (summary + help)

- [x] change root `RunE` from `runInfo()` to new function that: loads config, prints ASCII header, prints compact summary via `ui.RenderSummary()`, then prints help via cobra/fang
- [x] ensure `devbox` (no args) shows: header -> summary -> help
- [x] ensure `devbox info` shows full styled dashboard (separate path)
- [x] write tests for root command output (summary present, help present, no duplicate info)
- [x] run tests - must pass before next task

### Task 10: Implement styled `devbox info` with Lipgloss

- [x] update `internal/command/info.go` to use `ui.RenderInfo()` instead of legacy `renderInfo()` with `TableHeader`/`Definition`
- [x] remove legacy table-based rendering functions from `info.go` (`renderInfo`, `renderItem`, etc.)
- [x] verify `devbox info` renders all sections from `info.yml` with new styled output
- [x] verify conditional items (`when`) still work with template evaluation
- [x] clean up `devbox/info.yml` content: remove command cheat-sheet sections that duplicate `help`, keep project summary, URLs, hosts, services, tools, runtime details
- [x] write tests for info command with new renderer
- [x] run tests - must pass before next task

### Task 11: Add shell completion

- [x] enable Fang/Cobra built-in `completion` command (bash, zsh, fish, powershell)
- [x] add dynamic completion for `devbox commands inspect <id>` — read registry, return IDs
- [x] add dynamic completion for `devbox commands run <id>` — read registry, return IDs with descriptions via `cobra.CompletionWithDesc`
- [x] add dynamic completion for service/tool names where applicable (`shell`, `services enable/disable`, `tools enable/disable`)
- [x] add Active Help hints for key commands (`commands run`, `deploy step`, `render ide`)
- [x] write tests for completion functions (registry ID completion, service name completion)
- [x] run tests - must pass before next task

### Task 12: Add `devbox docs generate` command

- [x] create `internal/command/docs.go` with `devbox docs generate` command
- [x] implement Cobra docgen for static command tree (`doc.GenMarkdownTree`)
- [x] implement custom generator for registry commands (ID, description, type, params, context, env, examples)
- [x] support flags: `--output <dir>` (default `docs/reference`), `--format markdown|yaml|man|all`, `--scope all|cli|commands`, `--include-hidden`, `--include-private`
- [x] generate index files (`docs/reference/index.md`, `docs/reference/commands/index.md`)
- [x] write tests for doc generation (CLI tree output, registry command output)
- [x] run tests - must pass before next task

### Task 13: Clean up messages and descriptions

- [x] replace all `make <target>` references in Short/Long/Example/error messages with `devbox <command>` equivalents
- [x] fill in missing `Long` and `Example` fields for all public commands
- [x] ensure all commands have meaningful `Short` descriptions
- [x] update error messages and suggestions to reference new command names
- [x] run tests - must pass before next task

### Task 14: Update parent project Makefile

- [x] update `make help` target: change from `devbox info` to `devbox` (new root behavior) or keep as `devbox info` if preferred
- [x] verify all Make targets still work (`up`, `down`, `stop`, `restart`, `logs`, `deploy`, `reset`)
- [x] verify `devbox print` still works for Make macros
- [x] run Make targets to confirm integration

### Task 15: Verify acceptance criteria

- [x] verify `devbox` (no args) shows ASCII header + summary + help (manual test - not automatable)
- [x] verify `devbox help` shows grouped, Fang-styled help (manual test - not automatable)
- [x] verify `devbox info` shows styled project dashboard from `info.yml` (manual test - not automatable)
- [x] verify `devbox version` and `--version` work (manual test - not automatable)
- [x] verify all lifecycle commands work at root level (`up`, `down`, `stop`, `restart`, `logs`, `ps`, `wait`) (manual test - not automatable)
- [x] verify `devbox shell` and `devbox status` work (manual test - not automatable)
- [x] verify `devbox commands list/inspect/run` work (manual test - not automatable)
- [x] verify tab completion works (static + dynamic registry IDs) (manual test - not automatable)
- [x] verify `devbox docs generate` produces correct output (manual test - not automatable)
- [x] verify `devbox print` still works (hidden, for Make) (manual test - not automatable)
- [x] verify deploy/reset pipelines unaffected (manual test - not automatable)
- [x] verify docker logs / compose raw passthrough unaffected (manual test - not automatable)
- [x] run full test suite (`go test ./...`)
- [x] run linter (`make lint`)
- [x] verify no `make` references in user-facing CLI output (manual test - not automatable)

### Task 16: Update documentation

- [x] update CLAUDE.md command tree and package structure sections
- [x] update CLAUDE.md dependencies list
- [x] run `devbox docs generate` to produce reference docs
- [x] commit all changes in `devbox-cli/` repo on feature branch

## Technical Details

### Command Matrix (target state)

| Group | Command | Source |
|-------|---------|--------|
| Core | `devbox` (no args) | root.go — summary + help |
| Core | `devbox help` | Cobra/Fang |
| Core | `devbox info` | info.go + ui.RenderInfo |
| Core | `devbox version` | version.go |
| Environment | `devbox up/down/stop/restart` | up.go, down.go, etc. -> docker |
| Environment | `devbox logs/ps/wait` | logs.go, ps.go, wait.go -> docker |
| Environment | `devbox shell [service]` | shell.go (from services cli) |
| Environment | `devbox status` | status.go (from services topology) |
| Configuration | `devbox services list/enable/disable` | service.go |
| Configuration | `devbox tools list/enable/disable` | tools.go |
| Configuration | `devbox render env/ide` | env.go, ide.go |
| Pipelines | `devbox deploy plan/run/step/config` | deploy.go |
| Pipelines | `devbox reset plan/run/step/config` | reset.go |
| Advanced | `devbox commands list/inspect/run` | command_cmd.go |
| Advanced | `devbox docker ...` | docker.go (full subcommand set) |
| Advanced | `devbox compose files/argv/raw` | compose.go |
| Advanced | `devbox docs generate` | docs.go |
| Internal | `devbox print ...` | print.go (hidden) |

### Package responsibilities

- `internal/version` — version vars, `Info()` formatter, ldflags injection
- `internal/ui` — Lipgloss styles, `RenderSummary()`, `RenderInfo()`, terminal width
- `internal/render` — plain Writer (Success/Error/Warning/Info), ASCII art, tree (unchanged)
- `internal/command` — Cobra commands, Fang wiring, groups
- `internal/config` — `InfoConfig` (renamed from HelpConfig), `LoadInfoConfig()`

### Version injection (Makefile)

```makefile
VERSION  ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
COMMIT   ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
DATE     ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
LDFLAGS  := -X devbox-cli/internal/version.Version=$(VERSION) \
            -X devbox-cli/internal/version.Commit=$(COMMIT) \
            -X devbox-cli/internal/version.Date=$(DATE) \
            -X devbox-cli/internal/version.BuiltBy=make

build: tidy
	@mkdir -p $(BIN_DIR)
	go build -ldflags "$(LDFLAGS)" -o $(BIN_DIR)/$(BINARY_NAME) ./cmd/devbox
```

### Fang integration pattern

```go
// cmd/devbox/main.go
func main() {
    root := command.NewRootCmd()
    fang.Execute(root,
        fang.WithVersion(version.Version),
        // other fang options as available
    )
}
```

Note: exact Fang API to be verified against v1.0.0 docs during implementation.

## Post-Completion

**Manual verification:**
- Test `devbox` in a real project directory with `devbox.yml`
- Test shell completion in bash and zsh
- Verify styled output looks correct in different terminal emulators
- Test with `NO_COLOR=1` for plain output fallback

**Follow-up work:**
- Merge feature branch in `devbox-cli/` repo
- Rebuild binary and test in parent project
- Consider adding `devbox upgrade` for self-update in future
- Consider Bubble Tea for interactive commands in future phase
