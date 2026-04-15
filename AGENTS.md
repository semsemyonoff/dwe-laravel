# Devbox Next — Laravel Pilot

Containerized local dev environment: Go CLI core + thin Make facade + Docker Compose runtime.

## Goals

The project exists to solve the "Make-as-DSL" problem in the legacy devbox, where orchestration, rendering, topology resolution, state management, and config are all tangled inside Makefiles and `.mk` includes. The new architecture separates concerns cleanly:

1. **Single source of truth in YAML** — `devbox.yml` + layered config files define the entire project declaratively. No implicit config scattered across `.mk` variables, `.env.default`, and Make recipes.
2. **CLI as shared core** — All logic that computes, validates, inspects, renders, or generates belongs in `devbox-cli` (Go). This includes: config merge, topology resolution, .env generation, info/help display, deploy plan generation, editor/devcontainer config.
3. **Make as thin execution layer** — Make only runs atomic actions: `run`, `stop`, `up`, `down`, `logs`, `exec`, project-specific commands. No orchestration, no rendering, no config resolution in Make.
4. **Generated .env as transport only** — `.env` is never edited manually, never a source of truth. It is rendered from the export spec by `devbox render env`.
5. **Explicit over magic** — No magic env variable name mapping. All exports are declared explicitly in `exports.env` rules with `name`, `from` (dot-path), `format`, `when`.
6. **Service as hub** — Each application service directory follows the hub model: `src/`, `configs/`, `logs/`, `home/`, `runtime/`, `.devcontainer/`.
7. **Incremental migration** — No big bang rewrite. Five phases, each delivering standalone value while preserving backward compatibility.
8. **Editor-agnostic** — Must support JetBrains, VS Code, and Zed equally via generated configurations.
9. **AI-friendly structure** — Predictable directory layout, declarative entities, safe extensibility. An agent or human should be able to understand the project state by reading config files without tracing Make logic.

## Design principles

### CLI (Go)
- Go is the only language for CLI (cross-platform binary, no runtime dependencies).
- CLI is the single control plane for Docker Compose. `devbox docker` is the public lifecycle API; `devbox compose` is the low-level diagnostic layer. No direct `docker compose` calls in Makefiles, YAML commands, or deploy steps.
- Keep packages focused: `config` (loading/merging), `render` (ANSI output), `tpl` (templates), `command` (cobra wiring), `docker` (compose execution).
- Errors bubble up with `fmt.Errorf` wrapping. Root command catches and renders them via `render.Stdout().Error()`.
- Minimal dependencies. Current set: cobra, yaml.v3, go-figure. Do not add dependencies without strong justification.
- All user-visible output formatting lives in the `render` package. Make recipes must not produce styled output directly — they call CLI print subcommands via macros.

### Config
- Three layers merged in strict order: `devbox.yml` (structure) → `devbox/defaults.yml` (versioned defaults) → `devbox/local.yml` (gitignored user overrides). Later wins, maps merge recursively.
- `devbox.yml` is lean — only project identity and service structure. Runtime details (ports, hosts, tools, state) live in `defaults.yml`.
- Export rules are declarative and live in `defaults.yml` under `exports.env`. Each rule maps a dot-path in the merged config to an env variable name.
- `devbox/local.yml` is always gitignored. `devbox/local.example.yml` is the tracked template showing available overrides.
- Docker/Compose execution policy lives in `devbox/docker.yml` (tracked) + `devbox/docker.local.yml` (gitignored). Loaded separately by `LoadDockerConfig()`, not merged with the 3-layer devbox config. Controls project name, global/per-command compose args, and .env auto-generation triggers.

### Make
- All user-visible output goes through CLI macros: `$(call ok,...)`, `$(call err,...)`, `$(call warn,...)`, `$(call inf,...)`. Defined in `make/macros.mk`.
- Public targets use `snake_case`. Internal targets use `private_*` prefix.
- Use `@` to suppress command echo in recipes.
- Makefile includes only `make/macros.mk`. Lifecycle targets (`up`, `down`, `stop`, `restart`, `logs`) delegate to `devbox docker`. No compose flag assembly, no `docker compose` calls in Make.
- Cross-platform: must work on macOS and Linux (including WSL). Prefer portable shell constructs.

### General
- Do not commit secrets to `.env` or config files.
- `legacy/` directory is gitignored and contains old devbox repos for reference only. Do not modify legacy code.
- `devbox-cli/` directory is gitignored (built separately). Binary output goes to `bin/devbox`.
- When adding new functionality, update both the CLI implementation and the relevant config schema/help definitions.

## Architecture

- **devbox-cli** (`devbox-cli/`) — Go binary, the shared core: config loading, rendering, env generation, info display, topology, deploy planning, docker control plane
- **Docker** — `devbox docker` is the public lifecycle API (up/down/stop/restart/logs/ps/exec/run/wait); `devbox compose` is the low-level diagnostic layer (files/argv/raw)
- **Make** (`Makefile` + `make/`) — thin facade that delegates lifecycle targets to `devbox docker`
- **Config** — 3-layer YAML merge: `devbox.yml` → `devbox/defaults.yml` → `devbox/local.yml` (gitignored)
- **Docker policy** — `devbox/docker.yml` + `devbox/docker.local.yml` (gitignored); loaded separately, controls compose execution (project name, args, .env triggers)
- **Deploy** — `devbox/deploy.yml` loaded separately (not merged); declares phases and steps
- `.env` is a **generated artifact** (`devbox render env -o .env`), never a source of truth

## Project layout

```
devbox.yml                          # structural spec: project + services
devbox/defaults.yml                 # versioned defaults: tools, runtime, ports, hosts, exports, compose, ide
devbox/deploy.yml                   # deploy pipeline declaration (phases + steps, loaded separately)
devbox/docker.yml                   # docker/compose execution policy (project name, args, env triggers)
devbox/docker.local.yml             # docker policy local overrides (gitignored)
devbox/docker.local.example.yml     # tracked template for docker policy overrides
devbox/local.yml                    # local overrides (gitignored)
devbox/local.example.yml            # tracked template for local overrides
devbox/help.yml                     # declarative info/help screen config
devbox/commands/                    # declarative command definitions (YAML, grouped by subdirectory)
devbox/commands/db.yml              # db group: db.up, db.wait, db.start (workflow)
devbox/commands/app.yml             # app group: app.install (installer container)
devbox/commands/services/main.yml   # services.main group: composer-install, key-generate, migrate, bootstrap
devbox/commands/services/main/db.yml       # services.main.db group: db.create (private)
devbox/commands/services/second.yml        # services.second group: mirror of main service commands
devbox/commands/services/second/db.yml     # services.second.db group: db.create (private)
Makefile                            # thin facade — calls ./bin/devbox; lifecycle targets only
make/macros.mk                      # output macros (ok, err, warn, inf) → devbox print
compose.yaml                        # base compose: nginx, db, redis, app-main (mandatory infrastructure)
compose/tools/adminer.yml           # Adminer DB tool overlay
compose/tools/redis_insight.yml     # Redis Insight GUI overlay
compose/tools/mailpit.yml           # Mailpit email testing overlay
compose/services/main/debug.yml     # app-main-debug container (Xdebug enabled)
compose/installer.yml               # installer container (deploy only)
configs/app/main/.env               # Laravel .env template (copied to services/main/configs/ on deploy)
services/                           # service hubs (gitignored, created by deploy)
devbox-cli/                         # Go module (gitignored, built separately into bin/)
legacy/                             # old devbox repos (gitignored)
```

### Compose naming convention

- `compose.yaml` at root — mandatory infrastructure (nginx, db, redis, app-main), always started
- `compose/tools/<name>.yml` — optional tool services (adminer, redis_insight, mailpit)
- `compose/services/<service>/<name>.yml` — optional service variants (debug container)
- `compose/installer.yml` — standalone installer (deploy only, not in regular compose files list)
- No `docker-compose.` prefix in overlay filenames

## devbox-cli

Go module at `devbox-cli/`, built to `bin/devbox`.

### Build & test

```bash
cd devbox-cli && make build   # → ../bin/devbox
cd devbox-cli && make test    # go test ./...
cd devbox-cli && make lint    # golangci-lint
```

### Package structure

- `cmd/devbox/main.go` — entry point
- `internal/config/` — `DevboxConfig` struct, layered `LoadConfig()`, `LoadDeployConfig()`, `LoadDockerConfig()`, `ResolvePath()`, `ExportRule`, `ComposeConfig`, `DockerConfig`, `DeployConfig`, `IDEConfig`
- `internal/docker/` — `Compose` struct for building and executing `docker compose` commands with policy args
- `internal/render/` — `Writer` with ANSI output methods (Success, Error, Warning, Info, Definition, TableHeader, ASCII art)
- `internal/tpl/` — Go template engine with `Render()`, `EvalCondition()`, custom `FuncMap` (`appURL`)
- `internal/commands/` — declarative command system: `CommandFile`, `Registry`, `HostRunner`, `DevboxRunner`, `ServiceExecRunner`, `ServiceRunRunner`, `ScriptRunner`, `WorkflowRunner`, param/context resolution, `${...}` template sugar
- `internal/command/` — cobra commands: `info`, `render env`, `render ide`, `print {success,warning,info,error}`, `docker {up,down,stop,restart,logs,ps,exec,run,wait,project-name}`, `compose {files,argv,raw}`, `services`, `deploy {plan,run,step,config}`, `command list`, `command inspect`, `command run`

### Dependencies

- `github.com/spf13/cobra` — CLI framework
- `gopkg.in/yaml.v3` — YAML parsing
- `github.com/common-nighthawk/go-figure` — ASCII art

### Key patterns

- Config layers merge via `deepMerge` (maps recurse, scalars: later wins)
- `DevboxConfig.Raw` holds the merged map for dot-path resolution in export rules
- Export rules (`defaults.yml` → `exports.env`) are declarative: `name`, `from` (dot-path), `format`, `when` (condition), `required`
- All `text`/`value`/`when` fields in `help.yml` support Go template expressions against `DevboxConfig`
- Errors bubble up with `fmt.Errorf` wrapping; root command silences cobra errors and renders via `render.Stdout().Error()`

## Config model

`devbox.yml` — project identity and service structure (tracked):
```yaml
project: { name: laravel, prefix: devbox }
services: { main: { type: app, dir: ./services/main } }
```

`devbox/defaults.yml` — tools, runtime, ports, hosts, export rules, compose overlays, ide config (tracked).

`devbox/deploy.yml` — deploy pipeline declaration: phases and steps (tracked, loaded separately by `LoadDeployConfig()`). Not merged with the 3-layer config.

`devbox/local.yml` — per-user overrides for state, tools, ports (gitignored). See `devbox/local.example.yml` for options.

### Config structs (key additions in Phases 2+)

- `ComposeConfig` — `Base string` + `Overlays map[string]string` (key → file path)
- `ServiceConfig` — adds `Container string`, `DirInternal string`, `Configs []ServiceConfigFile`
- `ServiceConfigFile` — `Src`, `Dest`, `Mode` (default/update/replace)
- `DeployConfig` — `Phases []DeployPhase`
- `DeployPhase` — `Name`, `Description`, `Steps []DeployStep`
- `DeployStep` — `Name`, `Cmd`, `Command`, `With`, `Description`, `When` (exactly one of Cmd/Command set; `Make` removed)
- `DockerConfig` — `ProjectName string`, `Args` (Global + per-command `[]string`), `Env` (AutoGenerate, Commands)
- `IDEConfig` — per-editor blocks: `VSCode`, `JetBrains`, `Devcontainer` (each with `Enabled bool`)

### Variable flow

```
devbox.yml + defaults.yml + local.yml
  → devbox render env -o .env    (CLI generates)
  → .env loaded by Make (-include .env)
  → .env loaded by Docker Compose (env_file)
  → Make targets use variables from .env (APP_MAIN_CONTAINER, DB_DATABASE, etc.)
```

### Deploy pipeline

Steps have three execution modes:
- `cmd: <command>` — shell command executed directly via `os/exec`
- `command: <id>` — declarative command ID resolved via the command registry (supports `with:` param overrides)
- `devbox: "<subcommand>"` — invokes a devbox CLI subcommand (e.g. `devbox: "docker up"`, `devbox: "docker wait"`)

`.env` generation is always the implicit first step (CLI inserts it before phase 1).

The `make:` step type has been removed. All service-level operations are now expressed as `command:` references pointing to YAML command definitions in `devbox/commands/`.

## Make macros

All Make output goes through CLI: `$(call ok,msg)`, `$(call err,msg[,exit_code])`, `$(call warn,msg)`, `$(call inf,msg)`. Defined in `make/macros.mk`.

## Migration phases

This repo is a pilot for migrating from the legacy devbox (Make-as-DSL) to a declarative architecture. Each phase delivers standalone value.

1. **Phase 1 — Rendering** (done): Move all output/help/summary from Make macros to CLI. Info display and .env generation work via `devbox info` and `devbox render env`. Make macros delegate to `devbox print`.
2. **Phase 2 — Config Orchestrator** (done): Merge config layers, compute enabled services/tools, resolve compose overlays, inspect topology — all in CLI. `devbox compose files`, `devbox services`, `devbox render ide`.
3. **Phase 3 — Deploy** (done): Declarative deploy phases in `devbox/deploy.yml`. CLI generates deploy plans (`devbox deploy plan`). Make executes steps via `deploy` target. `devbox deploy step`, `devbox deploy config` all implemented. Health polling (originally `devbox compose wait`) moved to `devbox docker wait` in Phase 5.
4. **Phase 4 — Commands System** (done): Declarative YAML command definitions in `devbox/commands/`. Six command types: `command`, `devbox`, `script`, `service_exec`, `service_run`, `workflow`. Deploy steps reference commands by ID. Make reduced to lifecycle targets only (`up`, `down`, `stop`, `restart`, `logs`, `deploy`, `deploy-reset`). `make/compose.mk`, `make/service.mk`, `make/deploy.mk` removed.
5. **Phase 5 — Docker Control Plane** (done): `devbox docker` is the single compose execution layer. Docker policy in `devbox/docker.yml`. Make lifecycle targets delegate to `devbox docker`. No direct `docker compose` calls in YAML commands or deploy steps. `devbox compose` retained as diagnostic layer (files/argv/raw).

### Success criteria

- Help/output independent of Make macros (Phase 1 — done)
- Services/tools computed via devbox-cli
- `.env` generated via export layer (Phase 1 — done)
- Deploy built via generated plan
- Config structure explicit and predictable
- Make thinner and more atomic
- Ready for editor/devcontainer generation layer
