# DWE — Laravel

A **demonstration project** for [DWE](#dwe-is-an-external-tool) (Dev Workspace Engine): a containerized local dev environment for a Laravel app, driven entirely by declarative YAML. `README.md` is the human-facing overview; this file is the working guide for agents editing the repo.

DWE augments the project's Docker Compose setup with configuration layering, lifecycle management, validation, and declarative tooling — it does **not** replace compose. Edit `docker-compose.yml` freely; DWE runs on top of it.

## DWE is an external tool

`dwe` is installed on the host (e.g. Homebrew at `/opt/homebrew/bin/dwe`). This repo contains only the project configuration it consumes — **do not** try to modify CLI behavior from here; only edit the YAML configs, compose files, and templates.

### Using the CLI

The CLI ships its own authoritative, versioned docs. Read them through the binary, always with `--lang en`:

```bash
dwe docs llms-txt --lang en             # project-aware overview / index — start here
dwe docs list --lang en                 # list every topic
dwe docs search <term> --lang en        # search docs
dwe docs show <topic> --lang en         # read one topic, e.g. reference/config/services/fields
```

**Rule — agents read status/data output as JSON.** When running `dwe validate`, `dwe status`, `dwe services`, or any other data-emitting status command, always pass `--output json` (alias `-o json`): the JSON is stable and parseable, while the default table output is formatted for humans and noisy to scan programmatically. **Exception — documentation:** the `dwe docs` commands (`show` / `list` / `search` / `llms-txt`) are not status commands — read them in their default form and never pass `-o json`. `docs show` / `docs llms-txt` emit markdown and treat `--output` as a *file path*, so `-o json` would write a file literally named `json` instead of changing the format.

**Read commands are safe to run:** `dwe status`, `dwe validate`, `dwe logs`, `dwe docs show/search/list/llms-txt`.

**Mutating commands change state — prepare the edit, then run deliberately (or ask the user):** `dwe deploy run`, `dwe run` / `stop` / `restart`, `dwe reset run`, `dwe services enable|disable`, `dwe docs generate`. **Never** call `docker compose` directly — DWE tracks state and holds locks.

After editing a `service.yml`, configs, or a service `deploy.yml` → `dwe deploy run`. After editing `docker-compose.yml` → `dwe run`. After toggling a service → `dwe services enable|disable <name> --apply`. After changing a `service.yml` icon/host → `dwe validate` to confirm.

## How this repo is configured

- **3-layer config merge**, strict order, later wins, maps merge recursively:
  `workspace.yml` (project identity only — `project.name`, `project.prefix`) → `workspace/defaults.yml` (versioned defaults: service toggles, runtime, exports, db) → `workspace/local.yml` (gitignored per-developer overrides; `local.example.yml` is the tracked template).
- **Services** are declared one-per-folder in `workspace/services/<name>/service.yml`, loaded separately and injected into the merged map. A `type:` discriminator (`app` / `tool` / `infra`) selects allowed fields. `required: true` services are always on (`main`); optional ones toggle via `services.<name>.enabled`. Per-service `ports:` / `hosts:` deep-merge by entry name. Each service can carry an `icon:` shown in `dwe info`.
- **`.env` is a generated artifact** (`dwe render env -o .env`), never edited by hand, never a source of truth. Every variable is declared explicitly in `defaults.yml` under `exports.env` (`name` + `from` dot-path + optional `format` / `when` / `default`). No magic name mapping.
- **Docker/Compose policy** lives in `workspace/docker.yml` (loaded separately, not part of the 3-layer merge). This project keeps it minimal — only the shared `composer_cache` volume; everything else uses DWE defaults (project name `dwe-laravel`, etc.).
- **Declarative commands** live in `workspace/commands/` — one file per group, subdirectories nest groups. Command IDs derive from path + filename + key (`workspace/commands/services/main/cache.yml` → `services.main.cache.*`).
- **Service hub model:** on deploy, each service gets a hub under `services/<name>/` (gitignored): `src/` (the app code), `configs/`, `home/`, `runtime/`, plus generated `.devcontainer/` / `.vscode/` / `AGENTS.md`.

### Pipeline files — what exists here

DWE's deploy / lifecycle / reset / info dashboards are all optional standalone files. **This project only defines `workspace/services/main/deploy.yml`** (the per-service deploy pipeline). It has no orchestrator `deploy.yml`, no `lifecycle.yml`, no `reset.yml`, no `info.yml` — so `dwe deploy run`, `dwe run`/`stop`/`restart`, `dwe reset run`, and `dwe info` all use DWE's built-in defaults. (`dwe validate` reports these as informational ⓘ, not errors.) Add a file from the `dwe docs` reference only when you need to customize that pipeline.

## Lifecycle

- `dwe deploy run` — full deploy: ensure hub dirs, install Laravel via the installer container, copy configs, start db, create database, composer install, key:generate, migrate, render IDE/AI configs. Run on first setup or after changing a service's config/deploy.
- `dwe run` / `dwe stop` / `dwe restart` — bring the stack up / down / cycle it.
- `dwe docker up|down|logs|exec|ps` — raw Docker Compose passthroughs (state-tracked).
- `dwe reset run` — destructive cleanup.

There is **no Make facade for lifecycle.** The `Makefile` exists for one thing only — building/pushing the multi-arch base PHP image (`make build-php-base-image`); day-to-day work goes through `dwe`.

## Project layout

```
workspace.yml                            # project identity (name/prefix)
workspace/defaults.yml                   # versioned defaults: service toggles, runtime, exports, db
workspace/local.yml                      # local overrides (gitignored)
workspace/local.example.yml              # tracked template for local overrides
workspace/docker.yml                     # docker/compose execution policy (shared composer_cache volume)
workspace/styles.yml                     # UI: ASCII header, color palette, separator
workspace/services/<name>/service.yml    # per-service declaration (type, container, icon, ports, hosts, dirs, cli, configs)
workspace/services/main/deploy.yml       # per-service deploy pipeline (the only pipeline file in this repo)
workspace/commands/                      # declarative commands (see "Commands" below)
workspace/scripts/db/*.sh                # scripts referenced by type:script commands (dump-create, dump-deploy)
workspace/templates/{ai,git,ide}/        # render packs consumed by `dwe render`
docker-compose.yml                       # base compose: nginx, db, app-main (mandatory infrastructure)
compose/tools/{dbgate,mailpit}.yml       # optional tool overlays
compose/services/main/debug.yml          # app-main-debug container (Xdebug)
compose/installer.yml                    # installer container (deploy only)
configs/services/main/.env               # Laravel .env template (copied into the hub on deploy)
services/                                 # service hubs (gitignored, created by deploy)
backups/                                  # local DB dumps (gitignored except .gitkeep)
.dwe/                                     # DWE runtime artifacts (gitignored): logs, state, snapshots, locks
legacy/                                   # old repos (gitignored, reference only — do not modify)
```

### Compose naming convention

- `docker-compose.yml` at root — mandatory infrastructure (nginx, db, app-main), always started (`compose.base`).
- `compose/tools/<name>.yml` — optional tool services (dbgate, mailpit).
- `compose/services/<service>/<name>.yml` — optional service variants (e.g. the debug container).
- `compose/installer.yml` — standalone installer (deploy only, not in the regular file list).
- No `docker-compose.` prefix on overlay filenames.

DWE assembles the `-f` list deterministically: base first, then enabled **tool** → **infra** → **app** overlays (alphabetical within each group).

## Commands

| ID group | File | Commands |
|----------|------|----------|
| `app.*` | `commands/app.yml` | `install` (installer container) |
| `db.*` | `commands/db.yml` | `create`, `drop`, `cli`, `dump-create`, `dump-deploy` (+ private `up`/`wait`/`start`) |
| `services.main` | `commands/services/main.yml` | `composer-install`, `key-generate`, `bootstrap` (+ private `chown-src`); the `queue` **daemon** |
| `services.main.db.*` | `.../main/db.yml` | `create` (private) |
| `services.main.log.*` | `.../main/log.yml` | `list`, `tail`, `copy`, `clean` |
| `services.main.cache.*` | `.../main/cache.yml` | `clear`, `config-clear`, `route-clear`, `view-clear`, `clear-all`, `optimize` |
| `services.main.migrate.*` | `.../main/migrate.yml` | `run`, `status`, `rollback`, `fresh`, `make` |
| `services.main.schedule.*` | `.../main/schedule.yml` | `list`, `run` |
| `services.main.queue.*` | `.../main/queue.yml` + daemon | `start`/`logs`/`stop`/`restart` (daemon), `failed`, `retry`, `failed-prune`, `clear` |
| `services.main.make.*` | `.../main/make.yml` | `model`, `controller`, `request`, `resource` |
| `services.main.artisan.*` | `.../main/artisan.yml` | `tinker`, `route-list`, `about`, `db-seed`, `storage-link` |

Run a command with `dwe cmd <id>`; pass params with `--set key=value` (e.g. `dwe cmd services.main.queue.start --set name=emails`). Each command declares a `type:` (`shell` / `dwe` / `script` / `service_exec` / `service_run` / `workflow` / `builtin` / `daemon`) — see `dwe docs show reference/config/commands/types --lang en`.

### The `main` deploy pipeline (`workspace/services/main/deploy.yml`)

Typed steps: each has a `type:` (`shell` / `dwe` / `command` / `builtin`) and `cmd:`, plus optional `when:` / `check:` / `continue_on_error`. `.env` generation is implicitly inserted before phase 1. Full schema: `dwe docs show reference/config/deploy/index --lang en`.

## Conventions

- Cross-platform: must work on macOS and Linux (including WSL).
- Don't commit secrets to `.env` or config files. `.env` is generated and gitignored.
- `legacy/` is gitignored, reference-only — do not modify it.
- Before editing any YAML under `workspace/`, confirm the schema with `dwe docs show reference/config/<area> --lang en` rather than guessing field shapes.
