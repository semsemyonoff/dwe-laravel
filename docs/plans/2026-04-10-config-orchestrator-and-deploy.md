# Config Orchestrator and Deploy

## Overview

Implement Phase 2 (Config Orchestrator) and Phase 3 (Deploy) of the devbox next-laravel pilot.

- **Phase 2** — CLI computes enabled services/tools, resolves Docker Compose overlays, outputs topology. Make calls CLI to get the right compose file list; no orchestration logic stays in Make.
- **Phase 3** — Declarative deploy phases in config. CLI generates a deploy plan as ordered steps. Make executes atomic steps from the generated plan.

This eliminates the last traces of orchestration logic from Makefiles and makes the full lifecycle (bring-up, deploy, teardown) driven by config + CLI.

## Context (from discovery)

- Files involved: `devbox-cli/`, `devbox.yml`, `devbox/defaults.yml`, `devbox/deploy.yml` (new), `Makefile`, `make/macros.mk`, `compose/` (to be created), `configs/` (to be created)
- Existing patterns: 3-layer YAML merge (`LoadConfig`), dot-path resolution (`ResolvePath`), cobra command tree (`root.go`), render package for ANSI output, export rules already declarative
- Phase 1 complete: `devbox info`, `devbox render env`, `devbox print` all working
- `DevboxConfig` struct is the extension point — new fields for compose overlays and deploy phases

### Directory structure (new)

```
devbox/
  defaults.yml                      # Versioned defaults: tools, runtime, ports, hosts, exports, compose
  deploy.yml                        # Deploy pipeline declaration (phases + steps)
  local.yml                         # Local overrides (gitignored)

compose.yaml                        # Base compose: nginx, db (mariadb), app-main (always running)

compose/                            # Optional compose overlays (tracked)
  tools/
    adminer.yml                     # Adminer DB tool
    redis_insight.yml               # Redis GUI
    mailpit.yml                     # Email testing
  services/
    main/
      debug.yml                     # app-main-debug container (Xdebug enabled)
  installer.yml                     # Installer container (deploy only)

configs/                            # Template configs for services (tracked)
  app/
    main/
      .env                          # Laravel .env template

services/                           # Service hubs (gitignored, created by deploy)
  main/
    src/                            # App source code (Laravel project)
    configs/                        # Deployed configs (.env copied from configs/app/main/)
    logs/                           # App logs (storage/logs mount)
    home/                           # Container user home dir
    runtime/                        # Runtime artifacts (profiler output, xdebug traces)
```

### Legacy reference (`legacy/devbox/`)

The legacy devbox (gitignored, read-only) implements the same concepts in Make — use it as reference.

**Compose file assembly (legacy `make/variables/compose/final.mk`):**
- Base: `-f docker-compose.yml` (always)
- Tools (if `DOCKER_COMPOSE_TOOLS_ENABLED=true`):
  - `-f compose/tools/docker-compose.adminer.yml` (if ADMINER_ENABLED)
  - `-f compose/tools/docker-compose.redis-insight.yml` (if REDIS_INSIGHT_ENABLED)
  - `-f compose/tools/docker-compose.mailpit.yml` (if MAILPIT_ENABLED)
- Debug: `-f compose/docker-compose.main-debug.yml` (if DEBUG_ENABLED)
- Logs: `-f compose/docker-compose.logs.yml` (if LOGS_ENABLED) — merging into base in new devbox
- Config: `-f compose/docker-compose.config.yml` (if CONFIG_ENABLED) — merging into base in new devbox
- Installer: `-f docker-compose.installer.yml` (in DOCKER_COMPOSE_ARG_ALL, for deploy only)

**Full deploy chain (legacy `make/commands/deploy.mk` + referenced targets):**
```
make deploy
  ├─ validate docker-compose.yml exists
  ├─ deploy_app_dir                        [deploy.mk:25]
  │  └─ deploy_app_dir_main                [deploy.mk:28-36]
  │     └─ mkdir projects/main/{src,logs,runtime,home,configs}
  ├─ deploy_main                           [deploy.mk:40-55]
  │  ├─ check if projects/main/src/* exists (skip if already deployed)
  │  ├─ deploy_app_dir_main (again)
  │  ├─ installer_new                      [installer.mk:5-10]
  │  │  └─ docker compose -p devbox-laravel -f docker-compose.installer.yml
  │  │     run -u $UID -w /var/www app-installer
  │  │     laravel new src --force --database=mariadb --phpunit -n
  │  ├─ config_copy_main                   [config.mk:58-63]
  │  │  └─ cp configs/app/main/.env → projects/main/configs/.env (replace mode)
  │  │     (apl_cnf macro handles modes: default/update/replace)
  │  ├─ up UPDATE_UID_GID=true             [Makefile:72-74]
  │  │  ├─ volume_create_composer_cache    [Makefile:161-172]
  │  │  │  └─ docker volume create devbox_composer_cache (if shared cache enabled)
  │  │  └─ docker compose up -d --remove-orphans
  │  ├─ (wait_all_healthy inlined)         [functions.mk:175-210]
  │  │  └─ for each container: poll health status, 30 attempts × 2s, timeout → error
  │  ├─ db_create                          [db.mk:34-39]
  │  │  └─ docker compose exec db mariadb -uroot -proot
  │  │     -e 'CREATE DATABASE laravel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'
  │  ├─ composer_install                   [app/main.mk:109-111]
  │  │  └─ docker compose exec -u $UID -w /var/www/app app-main
  │  │     composer install --prefer-dist --no-interaction --optimize-autoloader
  │  ├─ app_key_generate                   [app/main.mk:17-18]
  │  │  └─ docker compose exec -u $UID -w /var/www/app app-main
  │  │     php artisan key:generate
  │  └─ migrate                            [app/main.mk:38-39]
  │     └─ docker compose exec -u $UID -w /var/www/app app-main
  │        php artisan migrate
  ├─ install_completion (non-blocking)
  └─ help
```

**deploy_reset (legacy `deploy.mk:13-23`):**
```
make deploy_reset
  ├─ confirm (interactive y/n)
  ├─ make stop
  ├─ docker volume rm $(docker volume ls -q --filter name=devbox-laravel_*)
  ├─ rm -rf projects/*
  └─ success message
```

**Bring-up sequence (legacy `Makefile:46-55`):**
```
make run
  ├─ private_jobs_run_before (hooks from jobs.mk — extensible)
  ├─ up
  │  ├─ volume_create_composer_cache
  │  └─ docker compose up -d --remove-orphans
  ├─ wait_all_healthy (poll each container health)
  ├─ private_jobs_run_after (hooks)
  └─ help
```

**Key legacy macros:**
- `docker-compose = docker compose -p ${PROJECT_FULL} ${DOCKER_COMPOSE_ARG}` — compose with project name + file args
- `exec-cli-main = $(docker-compose) exec -u ${APPS_USER} -w /var/www/app app-main [cmd]`
- `exec-db = $(docker-compose) exec db mariadb -uroot -proot [opts] [sql]`
- `wait_all_healthy` — get container IDs, inspect health, poll 30×2s, error on timeout/unhealthy

**Config copy modes (legacy `config.mk:11-42`):**
- `default` — copy only if not exists
- `update` — AWK merge: adds new keys from template without overwriting existing values
- `replace` — overwrite unconditionally
- Source: `configs/app/<service>/<file>` → Dest: `projects/<service>/configs/<file>`

**IDE support (legacy — documented but NOT generated):**
- PhpStorm: remote interpreter via Docker Compose, Xdebug, CodeSniffer, path mappings
- VS Code: devcontainer.json attach to app-main, Xdebug launch.json, extensions
- Debug container: `app-main-dbg` with `PHP_ENABLE_XDEBUG=true`, DBGP_IDEKEY=PHPSTORM

**Key insights for new devbox:**
- Compose naming: drop `docker-compose.` prefix → `adminer.yml`, `debug.yml` etc.
- Base compose at root as `compose.yaml` (mandatory infra), overlays in `compose/` subdirs
- Logs/config overlays merged into base — no separate toggle, always on
- Deploy is a linear pipeline of atomic steps — perfect for declarative `deploy.phases[].steps[]`
- Each step must be independently runnable (no hidden Make prerequisites)
- Installer uses a separate compose file (`docker-compose.installer.yml`) — need equivalent
- `wait_all_healthy` is critical — needs CLI implementation or shell equivalent in step
- `UPDATE_UID_GID=true` on first deploy syncs container file permissions with host

## Development Approach

- **Testing approach**: Regular (implement first, then tests)
- Complete each task fully before moving to the next
- **Every task MUST include new/updated tests** for code changes
- **All tests must pass before starting next task**
- Run `cd devbox-cli && make test` after each task
- **For tasks modifying `devbox-cli/`**: also run `cd devbox-cli && make lint` — zero issues required before moving on
- Maintain backward compatibility with existing `make help` and `make env`

## Testing Strategy

- **Unit tests**: required for every task — add to existing `*_test.go` files or create new ones
- No e2e/UI tests; functional validation via `make` targets and CLI invocations is manual (Post-Completion)

## Progress Tracking

- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): code changes, tests, config schema
- **Post-Completion** (no checkboxes): manual smoke tests, Docker Compose bring-up verification

## Implementation Steps

### Task 1: Extend config schema for compose overlays

Add compose overlay declarations to `DevboxConfig` so CLI knows which compose files to use. New naming: base is `compose.yaml` at root, overlays in `compose/` subdirectories.

- [x] add `ComposeConfig` struct with `Base string` (single base file) and `Overlays map[string]string` (category/name → file path) in `devbox-cli/internal/config/devbox.go`
- [x] add `Compose ComposeConfig` field to `DevboxConfig`
- [x] add compose config to `devbox/defaults.yml`:
  ```yaml
  compose:
    base: compose.yaml
    overlays:
      adminer: compose/tools/adminer.yml
      redis_insight: compose/tools/redis_insight.yml
      mailpit: compose/tools/mailpit.yml
      debug: compose/services/main/debug.yml
  ```
- [x] write tests for loading compose config via `LoadConfig` (base present, overlays loaded correctly)
- [x] run tests + lint — must pass before task 2

### Task 2: Add `devbox compose files` command

Print resolved compose file list (base + enabled overlays), one per line. Make uses this for `-f` flags.

- [x] add `devbox-cli/internal/command/compose.go` with `newComposeCmd` and `newComposeFilesCmd`
- [x] implement `buildComposeFileList`: always emit base, then check tool/service enabled state for each overlay key (adminer/redis_insight/mailpit map to `cfg.Tools`, debug maps to a new `runtime.debug.enabled` flag or similar)
- [x] register `newComposeCmd(flags)` in `root.go`
- [x] write tests for `buildComposeFileList`: base only, one tool enabled, multiple tools, disabled excluded, debug on/off
- [x] run tests + lint — must pass before task 3

### Task 3: Add `devbox services` command

Print topology: services table + tools table. Single source of truth.

- [x] add `devbox-cli/internal/command/services.go` with `newServicesCmd`
- [x] implement: services table (name, type, dir, container) + tools table (name, enabled, port, host) using `render.Writer`
- [x] register `newServicesCmd(flags)` in `root.go`
- [x] write tests for data-building logic covering enabled/disabled tool rows
- [x] run tests + lint — must pass before task 4

### Task 4: Create Docker Compose files

Base `compose.yaml` at root (mandatory infrastructure). Overlays in `compose/` subdirectories (optional services/tools).

- [x] create `compose.yaml` — base services:
  - `nginx` — reverse proxy, volume-mounts `services/main/src`
  - `db` — mariadb, named volume for persistence, healthcheck
  - `app-main` — PHP-FPM, volume-mounts `services/main/src`, `services/main/home`, `services/main/logs`, env_file from `.env`
  - named network, named volumes
  - Logs and config concerns merged directly (no separate overlays)
- [x] create `compose/tools/adminer.yml` — adminer service
- [x] create `compose/tools/redis_insight.yml` — redis_insight service
- [x] create `compose/tools/mailpit.yml` — mailpit service
- [x] create `compose/services/main/debug.yml` — `app-main-debug` container (PHP_ENABLE_XDEBUG=true, mounts `services/main/runtime`)
- [x] create `compose/installer.yml` — installer container for `laravel new` (standalone, used only during deploy)
- [x] verify `devbox compose files` output matches file list
- [x] run existing tests — must pass before task 5

### Task 5: Extend service config schema

Template configs in `configs/` (tracked). Service declares its config files and container identity in `devbox/defaults.yml`. CLI uses this during deploy to copy/merge configs.

- [x] create `configs/app/main/.env` — Laravel .env template (DB_HOST=db, REDIS_HOST=redis, etc. matching compose service names)
- [x] extend `ServiceConfig` struct: add `Container string`, `DirInternal string` (workdir inside container, e.g. `/var/www/app`), `Configs []ServiceConfigFile` (with `Src`, `Dest`, `Mode` fields)
- [x] add `ServiceConfigFile` struct: `Src string` (template path), `Dest string` (filename in configs/), `Mode string` (default/update/replace)
- [x] add service config to `devbox/defaults.yml`:
  ```yaml
  services:
    main:
      type: app
      dir: ./services/main
      container: app-main
      dir_internal: /var/www/app
      configs:
        - src: configs/app/main/.env
          dest: .env
          mode: replace
  ```
- [x] write tests for loading service config with Container, DirInternal, Configs fields
- [x] run tests + lint — must pass before task 6

### Task 6: Extend config schema for deploy phases

Deploy pipeline lives in a separate `devbox/deploy.yml` (tracked, not part of the 3-layer merge). Each step is atomic. Steps have two execution modes: `cmd:` for shell commands and `make:` for calling Make targets. This is important because some Make targets (e.g. `up`, `stop`, `db_create`) are used both during deploy and in regular operation.

`.env` generation is always the implicit first step of any deploy — the CLI inserts it automatically before phase 1, because Make and compose both depend on `.env` for variables.

- [x] add structs in `devbox-cli/internal/config/devbox.go`:
  - `DeployConfig` with `Phases []DeployPhase`
  - `DeployPhase` with `Name string`, `Description string`, `Steps []DeployStep`
  - `DeployStep` with `Name string`, `Cmd string`, `Make string`, `Description string`, `When string`
  - A step must have exactly one of `Cmd` or `Make` set (not both)
- [x] add `Deploy DeployConfig` field to `DevboxConfig`
- [x] add `LoadDeployConfig(deployPath string)` function that loads `devbox/deploy.yml` separately (not merged with the 3-layer config)
- [x] update `LoadConfig` to also load `devbox/deploy.yml` if present and populate `cfg.Deploy`
- [x] create `devbox/deploy.yml` — full pipeline matching legacy:
  ```yaml
  # Deploy pipeline declaration.
  # Steps execute sequentially within each phase.
  # .env generation is always performed first (implicit, not listed).
  #
  # Step types:
  #   cmd:  — shell command (executed directly)
  #   make: — Make target (executed via make -f Makefile <target>)
  #
  # Steps with make: can also be called during regular operation (e.g. make up).
  # Steps with when: are skipped if the config path resolves to falsy.

  phases:
    - name: setup
      description: Prepare service directories and install application
      steps:
        - name: create-dirs
          cmd: mkdir -p services/main/{src,configs,logs,home,runtime}
          description: Create service hub directories
        - name: install
          cmd: >-
            docker compose -f compose/installer.yml
            run --rm -u $(id -u) -w /var/www app-installer
            laravel new src --force --database=mariadb --phpunit -n
          description: Install Laravel project via installer container
        - name: copy-configs
          cmd: devbox deploy config main
          description: Copy template configs to service directory
    - name: start
      description: Start containers and wait for health
      steps:
        - name: up
          make: up
          description: Start all containers
        - name: wait-healthy
          cmd: devbox compose wait
          description: Wait for all containers to become healthy
    - name: init
      description: Initialize application (database, dependencies, keys)
      steps:
        - name: db-create
          make: db_create
          description: Create application database
        - name: composer-install
          make: composer_install
          description: Install PHP dependencies
        - name: key-generate
          make: key_generate
          description: Generate Laravel application key
        - name: migrate
          make: migrate
          description: Run database migrations
  ```
- [x] write tests for loading deploy config: phases present, step with `run`, step with `make`, step with `when`, validation that step has exactly one of run/make
- [x] run tests + lint — must pass before task 7

### Task 7: Add `devbox deploy plan` command

Output resolved deploy plan. Evaluates `when` conditions. Shows step type (run/make) and the implicit `.env` generation step.

- [x] add `devbox-cli/internal/command/deploy.go` with `newDeployCmd` and `newDeployPlanCmd`
- [x] implement: load config (including deploy.yml), always prepend implicit `.env` generation step, iterate phases/steps, evaluate `when` via `tpl.EvalCondition`, print phase headers + step name/type/description/command
- [x] `table` format (default): human-readable, shows phase headers, step type badge `[run]`/`[make]`, description
- [x] `shell` format: emit executable commands — `cmd:` steps as-is, `make:` steps as `make <target>`
- [x] register `newDeployCmd(flags)` in `root.go`
- [x] write tests: truthy `when` included, falsy `when` excluded, no `when` always included, empty phases → empty, implicit .env step always first, both run/make step types rendered correctly in both formats
- [x] run tests + lint — must pass before task 8

### Task 8: Add `devbox deploy step` command

Run a single named deploy step by `<phase>/<step>` address. Handles both `cmd:` (exec shell command) and `make:` (exec `make <target>`) step types.

- [x] implement `newDeployStepCmd` in `deploy.go`: find step by `<phase>/<step>`, evaluate `when`, dispatch based on step type:
  - `cmd:` → exec via `os/exec`
  - `make:` → exec `make -f Makefile <target>` via `os/exec`
- [x] add `--dry-run` flag that prints the resolved command without executing
- [x] write tests: step with `cmd:` executed, step with `make:` dispatched correctly, step not found → error, when=false → skip with message, dry-run prints command for both types
- [x] run tests + lint — must pass before task 9

### Task 9: Add `devbox deploy config` command

Copy/merge template configs to service directories. Replaces legacy `config_copy_%` / `apl_cnf` macro.

- [ ] add `newDeployConfigCmd` in `deploy.go`: takes service name arg, reads `ServiceConfig.Configs[]`, for each entry copies `Src` → `services/<name>/configs/<Dest>` using `Mode`
- [ ] implement copy modes:
  - `default` — skip if destination exists
  - `replace` — overwrite
  - `update` — for `.env` files, merge new keys without overwriting existing (port of legacy AWK logic)
- [ ] write tests: default mode skips existing, replace overwrites, update merges new keys preserving existing values
- [ ] run tests + lint — must pass before task 10

### Task 10: Add `devbox compose wait` command

Health check polling — replaces legacy `wait_all_healthy`. Polls each container's health status with timeout.

- [ ] add `newComposeWaitCmd` in `compose.go`: get container IDs via `docker compose ps -q`, inspect health status, poll with configurable interval/timeout
- [ ] implement: for each container — if healthy: ok, if unhealthy: error, if starting: poll (default 30 attempts × 2s = 60s timeout), if no healthcheck: warn and skip
- [ ] add `--timeout` flag (default 60s) and `--interval` flag (default 2s)
- [ ] write tests for health-check parsing logic (mock docker output)
- [ ] run tests + lint — must pass before task 11

### Task 11: Update Makefile with compose-aware, deploy, and atomic service targets

Thin Make layer. Variables come from generated `.env` (loaded via `include .env`). Atomic targets are reusable — called both during deploy (via `make:` step type) and during regular operation.

- [ ] add `make/compose.mk`:
  - `COMPOSE_FILES` variable via `$(shell $(DEVBOX_BIN) compose files | sed 's/^/-f /' | tr '\n' ' ')`
  - `DOCKER_COMPOSE = docker compose -p $(PROJECT_FULL) $(COMPOSE_FILES)` macro
  - targets: `up`, `down`, `stop`, `restart`, `logs`
- [ ] add `make/service.mk` — atomic service targets (referenced by `deploy.yml` via `make:` steps, also usable standalone):
  - `db_create` — `$(DOCKER_COMPOSE) exec db mariadb -uroot -proot -e 'CREATE DATABASE IF NOT EXISTS $(DB_DATABASE) ...'`
  - `composer_install` — `$(DOCKER_COMPOSE) exec -u $$(id -u) -w $(APP_MAIN_DIR_INTERNAL) $(APP_MAIN_CONTAINER) composer install ...`
  - `key_generate` — `$(DOCKER_COMPOSE) exec -u $$(id -u) -w $(APP_MAIN_DIR_INTERNAL) $(APP_MAIN_CONTAINER) php artisan key:generate`
  - `migrate` — `$(DOCKER_COMPOSE) exec -u $$(id -u) -w $(APP_MAIN_DIR_INTERNAL) $(APP_MAIN_CONTAINER) php artisan migrate`
  - Variables (`APP_MAIN_CONTAINER`, `APP_MAIN_DIR_INTERNAL`, `DB_DATABASE` etc.) come from `.env`
- [ ] add `make/deploy.mk`:
  - `deploy` target: first runs `devbox render env -o .env`, then calls `devbox deploy plan --format=shell | sh` or iterates steps
  - `deploy_reset` target: confirm → stop → remove volumes (filter by project name) → rm -rf services/* → success message
- [ ] update `Makefile`:
  - `-include .env` at the top (load generated variables, `-` to not fail if missing)
  - `include make/compose.mk`, `include make/service.mk`, `include make/deploy.mk`
  - `PROJECT_FULL` derived from `.env` variables or `$(shell $(DEVBOX_BIN) config get project.prefix)-$(shell $(DEVBOX_BIN) config get project.name)`
- [ ] verify `make help` and `make env` still work
- [ ] run `cd devbox-cli && make test` — must pass before task 12

### Task 12: Design IDE/devcontainer config generation

`devbox render ide` generates IDE-specific configs into service directories. Language-agnostic design with PHP/Laravel templates for this pilot.

- [ ] add `IDEConfig` section to `DevboxConfig` with per-editor blocks: `vscode`, `jetbrains`, `devcontainer` — each with `enabled bool`
- [ ] add `ide:` section to `devbox/defaults.yml` with defaults for Laravel pilot
- [ ] add `devbox-cli/internal/command/ide.go` with `newRenderIDECmd` under existing `render` parent
- [ ] implement: for each enabled editor, render Go templates into `services/<name>/.devcontainer/`, `services/<name>/.vscode/`, `services/<name>/.idea/` using `DevboxConfig` data
- [ ] create initial templates:
  - `devcontainer.json` (language-agnostic base + PHP extensions for this pilot)
  - `.vscode/launch.json` (Xdebug debug config)
  - `.vscode/settings.json` (PHP path, formatter)
- [ ] write tests for template rendering with different config values
- [ ] run tests + lint — must pass before task 13

### Task 13: Verify acceptance criteria

- [ ] verify `devbox compose files` returns correct file list for current tool config
- [ ] verify `devbox services` shows correct topology table
- [ ] verify `make up` / `make down` use CLI-derived compose file list
- [ ] verify `devbox deploy plan` shows all enabled steps matching legacy sequence
- [ ] verify `devbox deploy plan --format=shell` emits executable commands
- [ ] verify `devbox deploy step <phase>/<step>` runs a single step
- [ ] verify `devbox deploy config main` copies template .env with correct mode
- [ ] verify `devbox compose wait` polls container health
- [ ] verify `devbox render ide` generates devcontainer/vscode configs into `services/main/`
- [ ] verify `make help` and `make env` still work
- [ ] run full test suite (`cd devbox-cli && make test`) — all pass
- [ ] run linter (`cd devbox-cli && make lint`) — zero issues

### Task 14: Update documentation

- [ ] update `devbox/help.yml` to include new commands (`compose files`, `compose wait`, `services`, `deploy plan`, `deploy step`, `deploy config`, `render ide`)
- [ ] update `CLAUDE.md` / `AGENTS.md` with new directory structure, compose naming, commands, and config schema

## Technical Details

**Compose naming convention:**
- `compose.yaml` at root — mandatory infrastructure (nginx, db, app-main), always started
- `compose/tools/<name>.yml` — optional tool services (adminer, redis_insight, mailpit)
- `compose/services/<service>/<name>.yml` — optional service variants (debug container)
- `compose/installer.yml` — standalone installer (deploy only, not part of regular compose files list)
- No `docker-compose.` prefix in overlay filenames

**Compose file resolution:**
- `DevboxConfig.Compose.Base` = `compose.yaml` (always included)
- `DevboxConfig.Compose.Overlays` maps overlay key → file path
- `devbox compose files` emits base, then checks enabled state per overlay key:
  - `adminer`/`redis_insight`/`mailpit` → check `cfg.Tools.<name>.Enabled`
  - `debug` → check `cfg.Runtime.Debug.Enabled` (new field) or similar

**Config file layout:**
- `devbox.yml` — project identity + service structure (layer 1)
- `devbox/defaults.yml` — tools, runtime, ports, hosts, exports, compose overlays (layer 2)
- `devbox/local.yml` — user overrides (layer 3, gitignored)
- `devbox/deploy.yml` — deploy pipeline declaration (separate file, NOT merged with config layers)

**Deploy pipeline (`devbox/deploy.yml`):**
- Loaded separately by `LoadDeployConfig()`, then attached to `DevboxConfig.Deploy`
- Phases contain steps; steps are sequential within a phase
- **Step types:**
  - `cmd: <command>` — shell command, executed directly via `os/exec`
  - `make: <target>` — Make target, executed via `make <target>` (reuses atomic targets from `make/service.mk`)
  - Exactly one of `cmd` or `make` must be set per step
- **Implicit first step:** `.env` generation (`devbox render env -o .env`) is always performed before phase 1 — because Make targets and compose both read variables from `.env`
- `when: <dot-path>` — optional condition, step skipped if config value is falsy

**Variable flow:**
```
devbox.yml + defaults.yml + local.yml
  → devbox render env -o .env    (CLI generates)
  → .env loaded by Make (-include .env)
  → .env loaded by Docker Compose (env_file)
  → Make targets use variables from .env (APP_MAIN_CONTAINER, DB_DATABASE, etc.)
```

**Service hub structure** — `services/<name>/` is gitignored and created by `deploy setup/create-dirs`:
- `src/` — app source (volume-mounted to `/var/www/app`)
- `configs/` — deployed configs (copied from `configs/app/<name>/`)
- `logs/` — app logs (volume-mounted from container's `storage/logs`)
- `home/` — container user home (`/home/www-data`)
- `runtime/` — profiler output, xdebug traces, debug artifacts

**Config copy modes** (matching legacy `apl_cnf` macro):
- `default` — copy only if destination doesn't exist
- `update` — merge new keys into existing .env (preserving user values)
- `replace` — overwrite unconditionally

**Deploy step addressing** — `<phase>/<step>` (e.g. `setup/create-dirs`, `init/migrate`).

**Make variables:**
```makefile
-include .env                    # generated by devbox render env
COMPOSE_FILES = $(shell $(DEVBOX_BIN) compose files | sed 's/^/-f /' | tr '\n' ' ')
DOCKER_COMPOSE = docker compose -p $(PROJECT_FULL) $(COMPOSE_FILES)
```

**Atomic Make targets** (in `make/service.mk`) — used both by `deploy.yml` via `make:` steps and directly by developers:
```makefile
up:           $(DOCKER_COMPOSE) up -d --remove-orphans
down:         $(DOCKER_COMPOSE) down
stop:         $(DOCKER_COMPOSE) stop
db_create:    $(DOCKER_COMPOSE) exec db mariadb -uroot -proot -e '...'
composer_install: $(DOCKER_COMPOSE) exec ... composer install
key_generate: $(DOCKER_COMPOSE) exec ... php artisan key:generate
migrate:      $(DOCKER_COMPOSE) exec ... php artisan migrate
```

## Post-Completion

**Manual smoke tests:**
- `make deploy` creates service dirs, installs Laravel, copies configs, generates .env, brings up stack, waits for health, creates DB, runs composer/key/migrate
- `make up` / `make down` / `make stop` with correct compose file list
- `make deploy_reset` removes everything cleanly
- Disabling a tool in `devbox/local.yml` excludes it from `devbox compose files` and `make up`
- `devbox deploy plan` output matches legacy sequence
- `devbox deploy step init/migrate` runs migration independently
- IDE configs generated for VS Code devcontainer

**Deployment/external:**
- No external services or consuming projects to update at this stage
