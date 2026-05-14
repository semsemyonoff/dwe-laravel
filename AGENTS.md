# Devbox Next — Laravel Pilot

Containerized local dev environment: Go CLI core + thin Make facade + Docker Compose runtime.

## Goals

The project exists to solve the "Make-as-DSL" problem in the legacy devbox, where orchestration, rendering, topology resolution, state management, and config are all tangled inside Makefiles and `.mk` includes. The new architecture separates concerns cleanly:

1. **Single source of truth in YAML** — `devbox.yml` + layered config files define the entire project declaratively. No implicit config scattered across `.mk` variables, `.env.default`, and Make recipes.
2. **CLI as shared core** — All logic that computes, validates, inspects, renders, or generates belongs in `devbox-cli` (Go, separate repo). This includes: config merge, topology resolution, .env generation, info/help display, deploy plan generation, editor/devcontainer config.
3. **Make as thin execution layer** — Make only runs atomic actions: `run`, `stop`, `up`, `down`, `logs`, `exec`, project-specific commands. No orchestration, no rendering, no config resolution in Make.
4. **Generated .env as transport only** — `.env` is never edited manually, never a source of truth. It is rendered from the export spec by `devbox render env`.
5. **Explicit over magic** — No magic env variable name mapping. All exports are declared explicitly in `exports.env` rules with `name`, `from` (dot-path), `format`, `when`.
6. **Service as hub** — Each application service directory follows the hub model: `src/`, `configs/`, `logs/`, `home/`, `runtime/`, `.devcontainer/`.
7. **Editor-agnostic** — Must support JetBrains, VS Code, and Zed equally via generated configurations.
8. **AI-friendly structure** — Predictable directory layout, declarative entities, safe extensibility. An agent or human should be able to understand the project state by reading config files without tracing Make logic.

## devbox-cli is external

**`devbox-cli` is a separate repository** (located at `/Users/s/Projects/devbox/next/cli`). In this repo it is currently exposed as a **symlink** at `./devbox-cli/` for convenience and reference; the symlink will be removed in the future. **Do not modify CLI code from this repo** — make CLI changes in the upstream repository.

The CLI's own reference docs live under `devbox-cli/docs/reference/` (config schema, command reference, conditions). Treat these as authoritative for CLI behavior.

## Design principles

### Config (this repo)
- Three layers merged in strict order: `devbox.yml` (structure) → `devbox/defaults.yml` (versioned defaults) → `devbox/local.yml` (gitignored user overrides). Later wins, maps merge recursively.
- `devbox.yml` is lean — only project identity (`schema_version: "2"`, `project.name`, `project.prefix`) and an optional top-level `binaries:` block (engine policy, not layered). Runtime details (ports, hosts, tools, state) live in `defaults.yml`.
- Export rules are declarative and live in `defaults.yml` under `exports.env`. Each rule maps a dot-path in the merged config to an env variable name.
- `devbox/local.yml` is always gitignored. `devbox/local.example.yml` is the tracked template showing available overrides.
- Service definitions live in `devbox/services.yml` (loaded separately, not part of the 3-layer merge). Mandatory services force `enabled: true`; optional services are toggled via `defaults.yml` / `local.yml`.
- Docker/Compose execution policy lives in `devbox/docker.yml` (tracked) + `devbox/docker.local.yml` (gitignored). Loaded separately. Controls project name, global/per-command compose args, `.env` auto-generation triggers, topology hidden services, and shared Docker volumes.
- Pipelines (`devbox/deploy.yml`, `devbox/reset.yml`, `devbox/lifecycle.yml`) and per-service deploy files (`devbox/deploy/<service>.yml`) are loaded standalone and resolve `${...}` template expressions against the merged config.
- Declarative commands live in `devbox/commands/` (one file per group; subdirectories nest groups). Command IDs are derived from path + filename + key.

### Make
- All user-visible output goes through CLI macros: `$(call ok,...)`, `$(call err,...)`, `$(call warn,...)`, `$(call inf,...)`. Defined in `make/macros.mk`.
- Public targets use `snake_case`. Internal targets use `private_*` prefix.
- Use `@` to suppress command echo in recipes.
- Makefile includes only `make/macros.mk`. `make stop` / `make restart` delegate to `devbox stop` / `devbox restart` (full lifecycle pipelines driven by `devbox/lifecycle.yml`). `make up` / `make down` / `make logs` are thin passthroughs to `devbox docker up` / `devbox docker down` / `devbox docker logs`. No compose flag assembly, no `docker compose` calls in Make.
- Cross-platform: must work on macOS and Linux (including WSL). Prefer portable shell constructs.

### General
- Do not commit secrets to `.env` or config files.
- `legacy/` directory is gitignored and contains old devbox repos for reference only. Do not modify legacy code.
- `devbox-cli/` is a symlink to the upstream CLI repo (gitignored, will be removed). Built binary lives at `bin/devbox`.
- When adding a new feature touches CLI behavior, the change goes upstream in `devbox-cli`. Only the YAML configs and templates in this repo follow.

## Architecture

- **devbox-cli** (external repo, symlinked at `devbox-cli/`) — Go binary. The shared core: config loading, rendering, env generation, info display, topology, deploy planning, docker control plane. Built to `bin/devbox` via `cd devbox-cli && make build`.
- **Docker** — `devbox docker` is the public lifecycle API (up/down/stop/restart/logs/ps/exec/run); `devbox compose` is the low-level diagnostic layer (files/argv/raw). Container health-wait is a pipeline builtin (`docker_wait_healthy`), not a CLI command.
- **Make** (`Makefile` + `make/`) — thin facade that delegates lifecycle targets to `devbox run` / `devbox stop` / `devbox docker up` / `devbox docker down`.
- **Config** — 3-layer YAML merge: `devbox.yml` → `devbox/defaults.yml` → `devbox/local.yml` (gitignored).
- **Docker policy** — `devbox/docker.yml` + `devbox/docker.local.yml` (gitignored); loaded separately, controls compose execution (project name, args, `.env` triggers, topology, resources).
- **Deploy** — `devbox/deploy.yml` (orchestrator) + `devbox/deploy/<service>.yml` (per-service); declares phases and steps. The orchestrator inlines per-service pipelines at `deploy_services: true` in `depends_on` order.
- **Lifecycle** — `devbox/lifecycle.yml`; declares `run` and `stop` pipelines. `devbox run` = update probe → before-run hooks → docker up → wait healthy (`docker_wait_healthy` builtin) → after-run hooks → info → message. `devbox stop` = before-stop hooks → docker down → after-stop hooks → message. `devbox restart` = stop + run --no-update. Use `devbox docker up` / `devbox docker down` for raw Docker Compose passthroughs (the top-level `devbox up/down/logs/ps/wait` aliases were removed).
- **Reset** — `devbox/reset.yml`; destructive cleanup pipeline (confirm → docker down → remove volumes → remove generated dirs).
- `.env` is a **generated artifact** (`devbox render env -o .env`), never a source of truth.

## Project layout

```
devbox.yml                          # project identity (schema_version, project name/prefix, binaries)
devbox/services.yml                 # service declarations (container, dirs, cli, configs, extends)
devbox/defaults.yml                 # versioned defaults: tools, runtime, ports, hosts, exports, compose, ide, db
devbox/deploy.yml                   # orchestrator deploy pipeline
devbox/deploy/main.yml              # per-service deploy pipeline (main)
devbox/deploy/second.yml            # per-service deploy pipeline (second)
devbox/reset.yml                    # reset pipeline
devbox/lifecycle.yml                # run + stop pipelines
devbox/lifecycle.example.yml        # tracked template showing full lifecycle shape with hook phases
devbox/docker.yml                   # docker/compose execution policy
devbox/docker.local.yml             # docker policy local overrides (gitignored)
devbox/docker.local.example.yml     # tracked template for docker policy overrides
devbox/local.yml                    # local overrides (gitignored)
devbox/local.example.yml            # tracked template for local overrides
devbox/info.yml                     # declarative info dashboard
devbox/styles.yml                   # UI styles: ASCII header, color palette, separator
devbox/commands/                    # declarative command definitions (per-group YAML)
devbox/commands/db.yml              # db group: up, wait, create, drop, cli, start, dump-create, dump-deploy
devbox/commands/app.yml             # app group: install (installer container)
devbox/commands/services/main.yml   # services.main: composer-install, key-generate, migrate, bootstrap
devbox/commands/services/main/db.yml      # services.main.db: create (private workflow)
devbox/commands/services/second.yml       # services.second: mirror of main service commands
devbox/commands/services/second/db.yml    # services.second.db: create (private workflow)
devbox/scripts/                     # script files referenced by type:script commands (db/dump-create.sh, etc.)
devbox/templates/                   # static templates (e.g. ide/)
Makefile                            # thin facade — calls ./bin/devbox; lifecycle targets only
make/macros.mk                      # output macros (ok, err, warn, inf) → devbox print
compose.yaml                        # base compose: nginx, db, redis, app-main (mandatory infrastructure)
compose/tools/adminer.yml           # Adminer DB tool overlay
compose/tools/redis_insight.yml     # Redis Insight GUI overlay
compose/tools/mailpit.yml           # Mailpit email testing overlay
compose/services/main/debug.yml     # app-main-debug container (Xdebug enabled)
compose/services/second/app.yml     # app-second container overlay
compose/installer.yml               # installer container (deploy only)
configs/services/main/.env          # Laravel .env template (copied to services/main/configs/ on deploy)
docs/plans/                         # implementation plans (markdown)
docs/reference/                     # generated reference documentation (devbox docs generate)
docs/reference/cli/                 # cobra command reference (one file per command)
docs/reference/commands/            # declarative command registry reference (one file per command)
services/                           # service hubs (gitignored, created by deploy)
backups/                            # local DB dumps etc. (gitignored)
logs/                               # pipeline log files (deploy.log, run.log, stop.log)
devbox-cli/                         # SYMLINK to external CLI repo — reference only, will be removed
legacy/                             # old devbox repos (gitignored, reference only)
```

### Compose naming convention

- `compose.yaml` at root — mandatory infrastructure (nginx, db, redis, app-main), always started
- `compose/tools/<name>.yml` — optional tool services (adminer, redis_insight, mailpit)
- `compose/services/<service>/<name>.yml` — optional service variants (debug container, second app)
- `compose/installer.yml` — standalone installer (deploy only, not in regular compose files list)
- No `docker-compose.` prefix in overlay filenames

## CLI build

```bash
cd devbox-cli && make build   # → ../bin/devbox  (until the symlink is removed)
./bin/devbox docs generate    # → docs/reference/  (CLI + command reference)
```

For full CLI documentation see `devbox-cli/docs/reference/`:

- `config/index.md` — file inventory and loader topology
- `config/devbox.md` — devbox.yml / defaults.yml / local.yml (the 3-layer merge)
- `config/services.md` — services.yml
- `config/deploy.md` — deploy.yml / reset.yml (typed step model, conditions, builtins, file logging)
- `config/lifecycle.md` — lifecycle.yml (run/stop pipelines, update probe, hook phases)
- `config/conditions.md` — typed `when:` conditions and `check:` actions
- `config/docker.md` — docker.yml (compose policy, project name, env triggers, topology, resources)
- `config/commands.md` — declarative commands (types, params, context, files, workflows, templates)
- `config/info.md` — info dashboard configuration
- `config/styles.md` — ASCII header and color palette

## Pipeline step model (typed)

Pipeline steps in `deploy.yml`, `deploy/<service>.yml`, `reset.yml`, and `lifecycle.yml` use the **typed action model**. Each step has a `type:` and a `cmd:` plus optional `with:`:

| `type:` | `cmd:` payload | Notes |
|---------|----------------|-------|
| `shell` | `sh -c <command>` | Full shell semantics |
| `devbox` | devbox subcommand string (e.g. `"docker up"`) | Binary path resolved automatically |
| `command` | declarative command ID (e.g. `services.main.migrate`) | Dispatched via command registry; supports `with:` overrides |
| `builtin` | builtin name | In-process Go action; parameters via `with:` |

Optional per-step fields:

- `when:` — pre-condition (typed: `{type: builtin|shell|template, cmd|expr: ...}`). Step skipped when falsy. Available builtin predicates: `dir-exists`, `dir-missing`, `dir-empty`, `dir-not-empty`, `file-exists`, `file-missing`.
- `check:` — post-action (same typed shape as steps). Pipeline aborts when the action fails (skipped when `continue_on_error: true` and step body failed).
- `continue_on_error: true` — failed step reported as ✗ but pipeline continues. Useful on hook phases.

Phases also accept `when:` (typed condition) and `untracked: true` (suppress step output for the phase). The `deploy_services: true` marker phase is valid only in `deploy.yml`.

Available builtins (registered in `internal/builtin/`): `confirm`, `message`, `service_dirs_ensure`, `service_configs_copy`, `service_configs_check`, `docker_remove_project_volumes`, `remove_paths`.

`.env` generation is the implicit first step inserted by the CLI before phase 1.

The legacy shorthand keys (`run:`, `devbox:`, `command:`, `builtin:` directly on the step) are no longer supported. Workflow steps inside `type: workflow` commands are an exception — they keep the older `command:` / `confirm:` / `with:` / `when:` (string) shape.

## Variable flow

```
devbox.yml + defaults.yml + local.yml
  → devbox render env -o .env    (CLI generates)
  → .env loaded by Docker Compose (env_file)
  → Make targets and command env vars use the exported variables
```

## Pipeline file logging

Every pipeline command (`deploy`, `reset`, `run`, `stop`) supports a top-level `log:` field that toggles file logging at `logs/<pipeline>.log`. When enabled, devbox status messages and child-process stdout/stderr are teed to the log file (with ANSI codes stripped). Defaults differ by pipeline:

- `devbox/deploy.yml` — `log:` defaults to `true` (deploy keeps a record by default).
- `devbox/reset.yml` — `log:` defaults to `false`.
- `devbox/lifecycle.yml` `run:` / `stop:` — `log:` defaults to `false`.

Override per pipeline with an explicit `log: true` or `log: false`.

## Make macros

All Make output goes through CLI: `$(call ok,msg)`, `$(call err,msg[,exit_code])`, `$(call warn,msg)`, `$(call inf,msg)`. Defined in `make/macros.mk`.
