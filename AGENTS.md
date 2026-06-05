# DWE — Laravel

Containerized local dev environment driven by **DWE** (Dev Workspace Engine): a Go CLI core + a Docker Compose runtime.

DWE augments the project's Docker Compose setup with configuration layering, lifecycle management, validation, and tooling — it does not replace compose. Edit `docker-compose.yml` freely; DWE runs on top of it. All lifecycle operations go through `dwe` directly (no Make facade).

## Goals

The project keeps orchestration, rendering, topology resolution, state management, and config declarative. Concerns are separated cleanly:

1. **Single source of truth in YAML** — `workspace.yml` + layered config files define the entire project declaratively.
2. **CLI as shared core** — All logic that computes, validates, inspects, renders, or generates belongs in the `dwe` binary: config merge, topology resolution, .env generation, info/help display, deploy plan generation, editor/devcontainer config.
3. **Generated .env as transport only** — `.env` is never edited manually, never a source of truth. It is rendered from the export spec by `dwe render env`.
4. **Explicit over magic** — No magic env variable name mapping. All exports are declared explicitly in `exports.env` rules with `name`, `from` (dot-path), `format`, `when`.
5. **Service as hub** — Each application service directory follows the hub model: `src/`, `configs/`, `home/`, `runtime/`, `.devcontainer/`.
6. **Editor-agnostic** — Must support JetBrains, VS Code, and Zed equally via generated configurations.
7. **AI-friendly structure** — Predictable directory layout, declarative entities, safe extensibility. An agent or human should be able to understand the project state by reading config files.

## DWE is an external tool

`dwe` is installed on the host (e.g. via Homebrew at `/opt/homebrew/bin/dwe`); this repo contains only the project configuration it consumes. **Do not modify CLI behavior from this repo** — only the YAML configs, compose files, and templates here.

The CLI ships its own authoritative reference docs, accessed through the binary (always pass `--lang en`):

- `dwe docs llms-txt --lang en` — project-aware overview / index (start here)
- `dwe docs list --lang en` — list all topics
- `dwe docs search <term> --lang en` — search docs
- `dwe docs show <topic> --lang en` — read a topic (e.g. `reference/config/services/fields`)

Read commands (`dwe status`, `dwe validate`, `dwe logs`, `dwe docs show/search/list/llms-txt`) are safe to run. Mutating commands (`dwe deploy run`, `dwe run`/`stop`/`restart`, `dwe reset run`, `dwe services enable|disable`, `dwe docs generate`) change state — prepare the edit, then run them deliberately. Never call `docker compose` directly; DWE tracks state and holds locks.

## Design principles

### Config (this repo)
- Three layers merged in strict order: `workspace.yml` (structure) → `workspace/defaults.yml` (versioned defaults) → `workspace/local.yml` (gitignored user overrides). Later wins, maps merge recursively.
- `workspace.yml` is lean — only project identity (`project.name`, `project.prefix`). Runtime details (ports, hosts, exports, state, db) live in `defaults.yml`.
- Export rules are declarative and live in `defaults.yml` under `exports.env`. Each rule maps a dot-path in the merged config to an env variable name.
- `workspace/local.yml` is always gitignored. `workspace/local.example.yml` is the tracked template showing available overrides.
- Service definitions live one-per-folder in `workspace/services/<name>/service.yml` (loaded separately, not part of the 3-layer merge). A `type:` discriminator (`app` / `tool` / `infra`) selects the allowed fields. `required: true` services are always enabled; optional services are toggled via `services.<name>.enabled` in `defaults.yml` / `local.yml`. Per-service `ports:` / `hosts:` are deep-merged by entry name.
- Tools (dbgate, mailpit) are `type: tool` services; their compose overlay is activated automatically when the service is enabled.
- Docker/Compose execution policy lives in `workspace/docker.yml` (tracked) + `workspace/docker.local.yml` (gitignored). Loaded separately. Controls project name, per-command compose args, `.env` auto-generation triggers, topology hidden services, and shared Docker volumes.
- Pipelines (`workspace/deploy.yml`, `workspace/reset.yml`, `workspace/lifecycle.yml`) and per-service deploy files (`workspace/services/<name>/deploy.yml`) are loaded standalone and resolve `${...}` template expressions against the merged config.
- Declarative commands live in `workspace/commands/` (one file per group; subdirectories nest groups). Command IDs are derived from path + filename + key.

### General
- Lifecycle is driven through `dwe` directly: `dwe run` / `dwe stop` / `dwe restart` (full pipelines) and `dwe docker up` / `dwe docker down` / `dwe docker logs` (raw passthroughs). There is no Makefile.
- Never call `docker compose` directly — DWE tracks state and holds locks.
- Cross-platform: must work on macOS and Linux (including WSL).
- Do not commit secrets to `.env` or config files.
- `legacy/` directory is gitignored and contains old repos for reference only. Do not modify legacy code.
- DWE runtime artifacts live under `.dwe/` (gitignored): logs, deploy state, snapshot pointers, locks.

## Architecture

- **dwe** (external binary) — the shared core: config loading, rendering, env generation, info display, topology, deploy planning, docker control plane.
- **Docker** — `dwe docker` is the public lifecycle API (up/down/stop/restart/logs/ps/exec/run); `dwe compose` is the low-level diagnostic layer (files/argv/raw). Container health-wait is a pipeline builtin (`docker_wait_healthy`), not a CLI command.
- **Config** — 3-layer YAML merge: `workspace.yml` → `workspace/defaults.yml` → `workspace/local.yml` (gitignored). Per-service `workspace/services/<name>/service.yml` files are injected into the merged raw map.
- **Docker policy** — `workspace/docker.yml` + `workspace/docker.local.yml` (gitignored); loaded separately, controls compose execution (project name, args, `.env` triggers, topology, resources).
- **Deploy** — `workspace/deploy.yml` (orchestrator) + `workspace/services/<name>/deploy.yml` (per-service); declares phases and steps. The orchestrator inlines per-service pipelines at `deploy_services: true` in `depends_on` order.
- **Lifecycle** — `workspace/lifecycle.yml`; declares `run` and `stop` pipelines. `dwe run` = update probe → before-run hooks → docker up → wait healthy (`docker_wait_healthy` builtin) → after-run hooks → info → message. `dwe stop` = before-stop hooks → docker down → after-stop hooks → message. `dwe restart` = stop + run --no-update. Use `dwe docker up` / `dwe docker down` for raw Docker Compose passthroughs.
- **Reset** — `workspace/reset.yml`; destructive cleanup pipeline (confirm → docker down → remove volumes → remove generated dirs).
- `.env` is a **generated artifact** (`dwe render env -o .env`), never a source of truth.

## Project layout

```
workspace.yml                            # project identity (project name/prefix)
workspace/defaults.yml                   # versioned defaults: service toggles, runtime, exports, db, compose
workspace/local.yml                      # local overrides (gitignored)
workspace/local.example.yml              # tracked template for local overrides
workspace/services/<name>/service.yml    # per-service declaration (type, container, ports, hosts, dirs, cli, configs)
workspace/services/main/deploy.yml       # per-service deploy pipeline (main)
workspace/deploy.yml                     # orchestrator deploy pipeline
workspace/reset.yml                      # reset pipeline
workspace/lifecycle.yml                  # run + stop pipelines
workspace/lifecycle.example.yml          # tracked template showing full lifecycle shape with hook phases
workspace/docker.yml                     # docker/compose execution policy
workspace/docker.local.yml               # docker policy local overrides (gitignored)
workspace/docker.local.example.yml       # tracked template for docker policy overrides
workspace/info.yml                       # declarative info dashboard
workspace/styles.yml                     # UI styles: ASCII header, color palette, separator
workspace/commands/                      # declarative command definitions (per-group YAML)
workspace/commands/db.yml                # db group: up, wait, create, drop, cli, start, dump-create, dump-deploy
workspace/commands/app.yml               # app group: install (installer container)
workspace/commands/services/main.yml     # services.main: composer-install, key-generate, migrate, bootstrap
workspace/commands/services/main/db.yml  # services.main.db: create (private workflow)
workspace/scripts/                       # script files referenced by type:script commands (db/dump-create.sh, etc.)
workspace/templates/                     # render packs (ai/, git/, ide/) consumed by dwe render
docker-compose.yml                       # base compose: nginx, db, app-main (mandatory infrastructure)
compose/tools/dbgate.yml                 # DbGate DB tool overlay
compose/tools/mailpit.yml                # Mailpit email testing overlay
compose/services/main/debug.yml          # app-main-debug container (Xdebug enabled)
compose/installer.yml                    # installer container (deploy only)
configs/services/main/.env               # Laravel .env template (copied to services/main/configs/ on deploy)
services/                                # service hubs (gitignored, created by deploy)
backups/                                 # local DB dumps etc. (gitignored)
.dwe/                                    # DWE runtime artifacts (gitignored): logs, deploy state, snapshots, locks
legacy/                                  # old repos (gitignored, reference only)
```

### Compose naming convention

- `docker-compose.yml` at root — mandatory infrastructure (nginx, db, app-main), always started (declared as `compose.base`)
- `compose/tools/<name>.yml` — optional tool services (dbgate, mailpit)
- `compose/services/<service>/<name>.yml` — optional service variants (e.g. the debug container)
- `compose/installer.yml` — standalone installer (deploy only, not in regular compose files list)
- No `docker-compose.` prefix in overlay filenames

DWE assembles the compose `-f` file list deterministically: base file first, then enabled **tool** → **infra** → **app** overlays (alphabetical by service key within each group).

## CLI reference

DWE docs are versioned with the binary. Read them through the CLI (always `--lang en`):

```bash
dwe docs llms-txt --lang en              # project overview / index (start here)
dwe docs show reference/config/index --lang en
dwe docs show reference/config/workspace --lang en          # workspace.yml / defaults.yml / local.yml (3-layer merge)
dwe docs show reference/config/services/index --lang en     # per-service service.yml
dwe docs show reference/config/deploy/index --lang en       # deploy.yml / reset.yml (typed steps, builtins)
dwe docs show reference/config/lifecycle --lang en          # lifecycle.yml (run/stop, update probe, hooks)
dwe docs show reference/config/conditions --lang en         # typed when: / check: conditions
dwe docs show reference/config/docker --lang en             # docker.yml (compose policy, project name, topology)
dwe docs show reference/config/commands/index --lang en     # declarative commands
dwe docs show reference/config/info --lang en               # info dashboard
dwe docs show reference/config/styles --lang en             # ASCII header and color palette
```

## Pipeline step model (typed)

Pipeline steps in `deploy.yml`, `services/<name>/deploy.yml`, `reset.yml`, and `lifecycle.yml` use the **typed action model**. Each step has a `type:` and a `cmd:` plus optional `with:`:

| `type:` | `cmd:` payload | Notes |
|---------|----------------|-------|
| `shell` | `sh -c <command>` | Full shell semantics |
| `dwe` | dwe subcommand string (e.g. `"docker up"`) | Binary path resolved automatically |
| `command` | declarative command ID (e.g. `services.main.migrate`) | Dispatched via command registry; supports `with:` overrides |
| `builtin` | builtin name | In-process Go action; parameters via `with:` |

Optional per-step fields:

- `when:` — pre-condition (typed: `{type: builtin|shell|template, cmd|expr: ...}`). Step skipped when falsy. Available builtin predicates: `dir-exists`, `dir-missing`, `dir-empty`, `dir-not-empty`, `file-exists`, `file-missing`.
- `check:` — post-action (same typed shape as steps). Pipeline aborts when the action fails (skipped when `continue_on_error: true` and step body failed).
- `continue_on_error: true` — failed step reported as ✗ but pipeline continues. Useful on hook phases.

Phases also accept `when:` (typed condition) and `untracked: true` (suppress step output for the phase). The `deploy_services: true` marker phase is valid only in `deploy.yml`.

Available builtins: `confirm`, `message`, `service_dirs_ensure`, `service_configs_copy`, `service_configs_check`, `docker_remove_project_volumes`, `remove_paths`, `docker_wait_healthy`.

`.env` generation is the implicit first step inserted by the CLI before phase 1.

Workflow steps inside `type: workflow` commands are an exception to the typed model — they keep the older `command:` / `confirm:` / `with:` / `when:` (string) shape.

## Variable flow

```
workspace.yml + defaults.yml + local.yml
  → dwe render env -o .env        (CLI generates)
  → .env loaded by Docker Compose (env_file)
  → containers and declarative command env vars use the exported variables
```

## Pipeline file logging

Every pipeline command (`deploy`, `reset`, `run`, `stop`) supports a top-level `log:` field that toggles file logging at `.dwe/logs/<pipeline>.log`. When enabled, dwe status messages and child-process stdout/stderr are teed to the log file (with ANSI codes stripped). Defaults differ by pipeline:

- `workspace/deploy.yml` — `log:` defaults to `true` (deploy keeps a record by default).
- `workspace/reset.yml` — `log:` defaults to `false`.
- `workspace/lifecycle.yml` `run:` / `stop:` — `log:` defaults to `false`.

Override per pipeline with an explicit `log: true` or `log: false`.
