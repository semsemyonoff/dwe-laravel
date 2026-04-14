# Commands System

## Overview
- Replace Make-based command orchestration with a declarative YAML command system in devbox-cli
- Commands are defined in `devbox/commands/**/*.yml` with automatic grouping from directory structure
- Five command types: `command`, `script`, `service_exec`, `service_run`, `workflow`
- Deploy pipeline refactored to reference commands by ID (dropping `make:` step type)
- Make becomes a thin lifecycle layer (`up`, `down`, `stop`, `restart`, `logs`, `deploy`, `deploy-reset`)
- Both repos (next-laravel + devbox-cli) get a `commands-system` branch

## Context (from discovery)
- **devbox-cli**: Go module at `devbox-cli/`, 8 packages, ~31 files. Key packages: `config`, `command`, `tpl`, `condition`, `render`
- **Existing deploy**: `DeployStep` has `Cmd`/`Make`/`ServiceConfigsCopy` fields, condition system in `internal/condition/`
- **Template engine**: `internal/tpl/` uses Go templates with `{{ }}` syntax; new system adds `${...}` sugar
- **Make targets to migrate**: `service.mk` (composer-install, key-generate, migrate, db-create, db-start, cli, app-install, config-copy-main), `deploy.mk` (deploy, deploy-plan, deploy-reset)
- **Make targets to keep in Makefile**: `up`, `down`, `stop`, `restart`, `logs` (from compose.mk), `deploy`, `deploy-plan`, `deploy-reset`, `help`, `env` plus `macros.mk` internals
- **Legacy commands reference**: `legacy/devbox/make/` — contains the original Make-based command implementations from the old devbox. Use as reference for porting commands to the new YAML command system (target names, shell logic, variable usage patterns)

## Development Approach
- **Testing approach**: Regular (code first, then tests)
- Complete each task fully before moving to the next
- Make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
- **CRITICAL: all tests must pass before starting next task** — no exceptions
- **CRITICAL: update this plan file when scope changes during implementation**
- Run tests after each change (`cd devbox-cli && make test && make lint`)
- Maintain backward compatibility during transition
- **Two repos**: devbox-cli changes go in `devbox-cli/` (separate git repo), project changes in root repo. Both use `commands-system` branch.
- **Commits in both repos**: after completing a task, commit changes in both repos as needed. `devbox-cli/` is a separate git repo — run `git add`/`git commit` inside `devbox-cli/` for Go code changes, and in the root repo for YAML/Make/config changes.

## Testing Strategy
- **Unit tests**: required for every task
- Config loading/parsing: test YAML unmarshalling, validation, ID computation
- Template interpolation: test `${...}` → Go template compilation
- Runners: test command building (not execution) where possible; integration tests for exec
- CLI commands: test output formatting, tree rendering
- Deploy refactor: update existing deploy tests for new step types

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with `+` prefix
- Document issues/blockers with `!` prefix
- Update plan if implementation deviates from original scope

## Implementation Steps

### Task 1: Branch setup and command schema types
- [x] Create `commands-system` branch in both repos (root next-laravel and devbox-cli)
- [x] Create `internal/commands/` package in devbox-cli
- [x] Define core types: `CommandFile`, `GroupMeta`, `CommandDef`, `ParamDef`, `ContextDef`, `ScriptDef`, `WorkflowStep`, `RunnerDef`
- [x] Define `CommandType` enum: `command`, `script`, `service_exec`, `service_run`, `workflow`
- [x] Define `ParamType` enum: `string`, `bool`, `int`, `path`
- [x] Define `UserMode` type: `current`, `root`, literal string
- [x] Define `ExecMode` type: `exec`, `run`, `exec-or-run`
- [x] Implement YAML unmarshalling with validation (mutually exclusive fields: `run`/`argv`, `script.path`/`script.plan+run+cleanup`, workflow uses `steps` not `run`)
- [x] Write tests for type definitions and YAML unmarshalling (valid cases)
- [x] Write tests for validation (invalid/conflicting field combinations)
- [x] Run tests and lint — must pass before next task

### Task 2: Command loader — file discovery and ID computation
- [x] Implement `DiscoverCommandFiles(baseDir string) ([]string, error)` — walk `devbox/commands/` recursively, collect `*.yml`
- [x] Implement `ComputeGroup(relPath string) string` — derive group segments from path (`index.yml` handling, directory segments)
- [x] Implement `ComputeCommandID(group string, localName string) string` — build full `<group>.<local_name>` ID
- [x] Implement `LoadCommandFile(path string) (*CommandFile, error)` — parse single YAML file, validate, set computed group
- [x] Write tests for file discovery with temp directory fixtures
- [x] Write tests for group computation (all path patterns from spec: `db.yml`, `services/main.yml`, `services/main/db.yml`, `services/main/index.yml`)
- [x] Write tests for ID computation
- [x] Run tests and lint — must pass before next task

### Task 3: Command registry
- [x] Implement `Registry` struct — holds all commands indexed by full ID, groups as tree
- [x] Implement `LoadRegistry(baseDir string) (*Registry, error)` — discover files, load all, build registry with duplicate ID detection
- [x] Implement `Registry.Get(id string) (*CommandDef, error)` — lookup by full ID
- [x] Implement `Registry.List(groupPrefix string) []*CommandDef` — list commands under a group prefix (excluding private)
- [x] Implement `Registry.ListAll(groupPrefix string) []*CommandDef` — list all commands including private
- [x] Implement `Registry.Groups() *GroupTree` — tree structure for display
- [x] Implement `Registry.Validate() error` — cross-registry validation (workflow steps reference existing commands, service references valid services)
- [x] Write tests for registry building, lookup, listing, tree
- [x] Write tests for validation (missing workflow step references, duplicate IDs)
- [x] Run tests and lint — must pass before next task

### Task 4: Template interpolation — `${...}` syntax sugar
- [x] Implement `CompileVarSyntax(input string) string` in `internal/tpl/` — convert `${name}` to `{{ index .Raw "name" }}` (or appropriate Go template call)
- [x] Handle nested dot-paths: `${project.name}` → resolution against merged config raw map
- [x] Handle runtime helpers: `${host.uid}`, `${host.gid}` → injected into template data
- [x] Implement `RenderCommand(expr string, data *RenderContext) (string, error)` — compile `${...}`, then evaluate Go template
- [x] Define `RenderContext` struct — holds `Raw` config map, `Params` map, `Context` map, runtime helpers
- [x] Write tests for `CompileVarSyntax` (simple vars, dot-paths, mixed with Go templates, no-op for plain strings)
- [x] Write tests for `RenderCommand` with full context resolution
- [x] Write tests for edge cases (escaped `$`, `${` inside Go template blocks, missing values)
- [x] Run tests and lint — must pass before next task

### Task 5: Param and context resolution
- [x] Implement `ResolveParams(defs map[string]ParamDef, provided map[string]string, cfg *config.DevboxConfig) (map[string]any, error)` — apply defaults, `default_from` config paths, type coercion, required validation
- [x] Implement `ResolveContext(defs map[string]ContextDef, cfg *config.DevboxConfig) (map[string]any, error)` — resolve `from` config paths, required validation
- [x] Implement `BuildEnv(cmd *CommandDef, params map[string]any, context map[string]any) map[string]string` — build env map from `params.*.env`, `context.*.env`, and command-level `env` field
- [x] Write tests for param resolution (defaults, default_from, type coercion, required missing)
- [x] Write tests for context resolution (from paths, required missing)
- [x] Write tests for env building
- [x] Run tests and lint — must pass before next task

### Task 6: Runners — `command` and `service_exec`/`service_run`
- [x] Implement `Runner` interface: `Run(ctx RunContext) error`
- [x] Define `RunContext` — command def, resolved params, resolved context, render context, config, project root, stdout/stderr
- [x] Implement `HostRunner` — executes `run` (via `sh -c`) or `argv` (via `exec`) on host, with `cwd` and `env` templating
- [x] Implement `ServiceExecRunner` — builds `docker compose exec` command with service, user, workdir resolution (`workdir_from` config path), mode (`exec`/`run`/`exec-or-run` with container-running check)
- [x] Implement `ServiceRunRunner` — builds `docker compose run --rm` command with same resolution
- [x] Implement exec-or-run mode: check if container is running, pick exec or run accordingly
- [x] Implement `runner` field support: when `runner` is set, use its fields instead of top-level `service`/`user`/`workdir`/etc.
- [x] Write tests for HostRunner command building (run vs argv, cwd, env)
- [x] Write tests for ServiceExecRunner command building (service, user, workdir, workdir_from)
- [x] Write tests for exec-or-run mode logic
- [x] Run tests and lint — must pass before next task

### Task 7: Runners — `script` and `workflow`
- [ ] Implement `ScriptRunner` — execute script file(s) with contract env vars (`DEVBOX_ROOT`, `DEVBOX_COMMAND_ID`, `DEVBOX_TEMP_DIR`, `DEVBOX_NONINTERACTIVE`, `DEVBOX_PARAMS_JSON`, `DEVBOX_CONTEXT_JSON`)
- [ ] Support simple mode (`script.path`) and phased mode (`script.plan` → `script.run` → `script.cleanup` with guaranteed cleanup)
- [ ] Support `script.shell` override (default: `sh`)
- [ ] Implement temp dir creation and cleanup for `DEVBOX_TEMP_DIR`
- [ ] Implement `WorkflowRunner` — iterate `steps`, resolve command reference, handle `with` param overrides, execute each step sequentially
- [ ] Implement `confirm` step type in workflow — prompt user with message, abort on decline, skip in non-interactive mode
- [ ] Validate that private commands can be called from workflow but not directly
- [ ] Write tests for ScriptRunner (env contract, simple mode, phased mode, cleanup guarantee)
- [ ] Write tests for WorkflowRunner (step sequencing, param passing via `with`, confirm skipping)
- [ ] Run tests and lint — must pass before next task

### Task 8: CLI commands — `devbox command list/inspect/run`
- [ ] Add `command` subcommand to root cobra command
- [ ] Implement `devbox command list [group]` — tree-formatted output, hide private commands, show descriptions
- [ ] Implement `devbox command list --all [group]` — include private commands (marked with indicator)
- [ ] Implement `devbox command inspect <id>` — show full command definition: type, description, params, context, runner details
- [ ] Implement `devbox command run <id> [--set key=value...]` — resolve params from `--set` flags, resolve context from config, pick runner, execute
- [ ] Implement tree rendering in `internal/render/` — `WriteTree(tree GroupTree)` with proper indentation
- [ ] Integrate registry loading into config loading flow (load commands after config merge)
- [ ] Write tests for tree rendering output
- [ ] Write tests for `--set` flag parsing and param forwarding
- [ ] Write tests for command resolution and runner dispatch
- [ ] Run tests and lint — must pass before next task

### Task 9: Deploy refactoring
- [ ] Add `Command` field to `DeployStep` struct (command ID reference, mutually exclusive with `Cmd`/`Make`/`ServiceConfigsCopy`)
- [ ] Add `With` field to `DeployStep` struct (param overrides map for command references)
- [ ] Remove `Make` field from `DeployStep` struct
- [ ] Update `LoadDeployConfig` validation: `Command`+`With` is valid, `Make` rejected
- [ ] Update `resolveDeployPlan` / `resolvePhaseSteps`: resolve command references via registry
- [ ] Update `newDeployRunCmd` execution: when step has `Command`, delegate to command runner
- [ ] Update deploy plan display to show command IDs
- [ ] Migrate existing `devbox/deploy.yml` and `devbox/deploy/*.yml` — replace `make:` steps with `cmd:` or `command:` references
- [ ] Update existing deploy tests for new step types
- [ ] Write tests for command-reference step resolution
- [ ] Run tests and lint — must pass before next task

### Task 10: Make migration — command YAML files
- [ ] Create `devbox/commands/db.yml` — `db.up` (private), `db.wait` (private), `db.start` (private workflow)
- [ ] Create `devbox/commands/services/main.yml` — `composer-install`, `key-generate`, `migrate`, `bootstrap` (workflow)
- [ ] Create `devbox/commands/services/main/db.yml` — `db.create` (private)
- [ ] Create `devbox/commands/services/main/config.yml` — `config-copy` (private, replaces config-copy-main)
- [ ] Create `devbox/commands/services/second.yml` — mirror of main service commands for second
- [ ] Create `devbox/commands/services/second/db.yml` — db.create for second service
- [ ] Create `devbox/commands/app.yml` — `app.install` (installer container command)
- [ ] Verify all commands resolve and validate: `devbox command list`, `devbox command inspect` for each
- [ ] Run tests — must pass before next task

### Task 11: Make cleanup — consolidate Makefile
- [ ] Move `up`, `down`, `stop`, `restart`, `logs` targets from `compose.mk` into `Makefile` (inline, they're simple)
- [ ] Move `deploy`, `deploy-plan`, `deploy-reset` from `deploy.mk` into `Makefile`
- [ ] Remove `make/compose.mk`, `make/service.mk`, `make/deploy.mk` includes
- [ ] Keep `make/macros.mk` (internal output macros)
- [ ] Update Makefile to keep COMPOSE_FILES and DOCKER_COMPOSE macro (needed by up/down/etc.)
- [ ] Add `cli` and `cli-root` targets that delegate to `devbox command run` (or keep as simple Make targets)
- [ ] Verify `make up`, `make down`, `make deploy`, `make cli` all still work
- [ ] Run tests — must pass before next task

### Task 12: Verify acceptance criteria
- [ ] Verify `devbox command list` shows tree output with all migrated commands
- [ ] Verify `devbox command run services.main.bootstrap` executes full workflow
- [ ] Verify `devbox command run services.main.composer-install` works with exec-or-run mode
- [ ] Verify `devbox deploy run` works with command references in deploy steps
- [ ] Verify private commands are hidden from list but callable from workflows
- [ ] Verify `${...}` interpolation works in command definitions
- [ ] Run full test suite (unit tests)
- [ ] Run linter — all issues must be fixed

### Task 13: Verify deploy end-to-end
- [ ] Run `make deploy-reset` to clean up all service data and volumes
- [ ] Run `make deploy`, verify it completes without errors — if errors found: fix the issue first, then `make deploy-reset` to clean state, then retry `make deploy`
- [ ] Verify all enabled services and tools are accessible (check containers running, health status, HTTP endpoints responding)
- [ ] Run `make down` to stop all containers

### Task 14: [Final] Update documentation
- [ ] Update `devbox/help.yml` to reflect new `devbox command` CLI commands
- [ ] Update `devbox/local.example.yml` if any new overridable config added
- [ ] Update CLAUDE.md project layout and architecture sections

## Technical Details

### New Go package: `internal/commands/`

```
internal/commands/
  types.go       — CommandFile, CommandDef, ParamDef, ContextDef, ScriptDef, WorkflowStep, RunnerDef, enums
  loader.go      — DiscoverCommandFiles, LoadCommandFile, ComputeGroup, ComputeCommandID
  registry.go    — Registry struct, LoadRegistry, Get, List, Groups, Validate
  resolve.go     — ResolveParams, ResolveContext, BuildEnv
  runner.go      — Runner interface, RunContext
  runner_host.go — HostRunner (command type)
  runner_service.go — ServiceExecRunner, ServiceRunRunner
  runner_script.go — ScriptRunner
  runner_workflow.go — WorkflowRunner
```

### Template interpolation

`${project.name}` compiles to `{{ index .Raw "project" "name" }}` (or a custom `resolve` function).

Implementation approach:
- Regex: `\$\{([a-zA-Z_][a-zA-Z0-9_.]*)\}` → split on `.` → generate nested index call
- Add `resolve` template function to `FuncMap`: `resolve(raw map, dotPath string) any`
- So `${project.name}` becomes `{{ resolve .Raw "project.name" }}`
- This reuses existing `config.ResolvePath` logic

### Deploy step changes

Before:
```yaml
steps:
  - name: composer-install
    make: composer-install
```

After:
```yaml
steps:
  - name: composer-install
    command: services.main.composer-install
```

Or inline (no change):
```yaml
steps:
  - name: wait-healthy
    cmd: ./bin/devbox compose wait
```

### Makefile after cleanup

```makefile
MAKEFLAGS += --no-print-directory
DEVBOX_BIN := ./bin/devbox
-include .env

PROJECT_PREFIX ?= devbox
PROJECT_NAME   ?= laravel
PROJECT_FULL    = $(PROJECT_PREFIX)-$(PROJECT_NAME)

include make/macros.mk

# Compose setup
ifneq ($(wildcard $(DEVBOX_BIN)),)
COMPOSE_FILES := $(shell $(DEVBOX_BIN) compose files | sed 's/^/-f /' | tr '\n' ' ')
endif
DOCKER_COMPOSE_FLAGS ?= --ansi always --progress tty
DOCKER_COMPOSE = docker compose $(DOCKER_COMPOSE_FLAGS) -p $(PROJECT_FULL) $(COMPOSE_FILES)

all: help

help:
	@$(DEVBOX_BIN) info

env:
	@$(DEVBOX_BIN) render env -o .env
	@$(call ok,.env generated)

up:
	@$(DOCKER_COMPOSE) up -d --remove-orphans

down:
	@$(DOCKER_COMPOSE) down

stop:
	@$(DOCKER_COMPOSE) stop

restart:
	@$(DOCKER_COMPOSE) restart

logs:
	@$(DOCKER_COMPOSE) logs -f

cli:
	@$(DEVBOX_BIN) command run services.main.cli

deploy-plan:
	@$(DEVBOX_BIN) deploy plan

deploy:
	@$(DEVBOX_BIN) deploy run
	@$(call ok,Deploy complete)

deploy-reset:
	@printf "This will stop containers and remove all service data. Continue? [y/N] " && \
		read -r ans && \
		if [ "$$ans" != "y" ] && [ "$$ans" != "Y" ]; then \
			$(call err,Aborted); exit 1; \
		fi
	@$(MAKE) down || true
	@[ -n "$(PROJECT_FULL)" ] || { $(call err,PROJECT_FULL is empty,1); }
	@VOLS=$$(docker volume ls -q | grep "^$(PROJECT_FULL)_"); \
		[ -z "$$VOLS" ] || docker volume rm $$VOLS
	@rm -rf services/
	@$(call ok,Reset complete)
```

## Post-Completion
*Items requiring manual intervention or external systems — no checkboxes, informational only*

**Manual verification:**
- Run `make deploy` end-to-end on a clean checkout to verify full pipeline
- Test `devbox command run` for each migrated command interactively
- Verify `cli` / `cli-root` targets work with exec-or-run mode
- Test with second service enabled to verify multi-service commands

**Follow-up work:**
- Port legacy devbox commands (OpenSearch snapshot, etc.) as command YAML files
- Add shell completion for `devbox command run <TAB>`
- Consider `devbox command create` scaffolding helper
