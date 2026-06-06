# DWE × Laravel — demonstration project

A reference project showing how to run a **Laravel** application's local development
environment with **DWE** (Dev Workspace Engine).

It is a showcase, not a production app: the Laravel source is installed on first deploy,
and everything around it — services, ports, hosts, the generated `.env`, lifecycle, and a
catalogue of everyday `php artisan` commands — is declared in YAML and orchestrated by DWE.

## What is DWE?

DWE is a host-installed CLI (a Go core + a Docker Compose runtime) that **augments** a
project's `docker-compose.yml` rather than replacing it. On top of plain Compose it adds:

- **Layered configuration** — `workspace.yml` → `workspace/defaults.yml` → `workspace/local.yml`,
  merged deterministically.
- **A generated `.env`** — rendered from an explicit export spec; never hand-edited.
- **Lifecycle management** — `dwe deploy` / `run` / `stop` / `restart` / `reset`, with state
  tracking and locking (so you never call `docker compose` directly).
- **Validation** — `dwe validate` checks config, templates, commands, and the environment.
- **Declarative commands** — project-specific tasks (artisan, queue, migrations, db dumps…)
  defined in YAML and runnable via `dwe cmd`.
- **Editor & agent config generation** — `.devcontainer`, `.vscode`, and `AGENTS.md`/`CLAUDE.md`
  rendered into each service hub.

## Requirements

- [Docker](https://docs.docker.com/get-docker/) (Desktop or Engine) with Compose v2
- The `dwe` CLI on your `PATH` (e.g. `brew install …`; run `dwe --version` to confirm)
- The hostnames below resolve to `127.0.0.1`. `*.localhost` resolves automatically on most
  systems; otherwise add them to `/etc/hosts`.

## Quick start

```bash
dwe deploy run     # first-time setup: install Laravel, start db, deps, key, migrate, render configs
dwe run            # bring the stack up
dwe status         # see what's running
dwe info           # project dashboard (URLs, services)
```

Then open **http://laravel.localhost**.

```bash
dwe stop           # stop the stack
dwe restart        # stop + run
dwe reset run      # destructive cleanup (removes volumes & generated dirs)
```

## Services

| | Service | Type | URL | Enabled by default |
|---|---------|------|-----|:---:|
| 🐘 | `main` — Laravel app (nginx + PHP-FPM) | app | http://laravel.localhost | ✅ (required) |
| 🐞 | `main-debug` — Xdebug-enabled variant of `main` | app | — | ❌ |
| 💾 | `dbgate` — multi-database GUI | tool | http://dbgate.localhost | ❌ |
| 📬 | `mailpit` — SMTP capture for local email testing | tool | http://mail.localhost | ✅ |

Plus base infrastructure from `docker-compose.yml`: an **nginx** reverse proxy and a **MariaDB**
database. Toggle optional services without touching defaults:

```bash
dwe services enable dbgate --apply
dwe services enable main-debug --apply
```

## Everyday commands

Run any command with `dwe cmd <id>`; pass parameters with `--set key=value`. A few highlights:

```bash
# Artisan utilities
dwe cmd services.main.artisan.tinker
dwe cmd services.main.artisan.route-list
dwe cmd services.main.artisan.about

# Caches
dwe cmd services.main.cache.clear-all          # php artisan optimize:clear
dwe cmd services.main.cache.optimize           # php artisan optimize

# Migrations
dwe cmd services.main.migrate.status
dwe cmd services.main.migrate.fresh --set seed=true
dwe cmd services.main.migrate.make --set name=add_status_to_orders

# Scaffolding
dwe cmd services.main.make.model --set name=Order --set migration=true --set controller=true

# Queue worker (background daemon) + failed-job management
dwe cmd services.main.queue.start --set name=default
dwe cmd services.main.queue.logs                # Ctrl-C detaches; worker keeps running
dwe status daemons
dwe cmd services.main.queue.failed
dwe cmd services.main.queue.retry --set id=all
dwe cmd services.main.queue.stop

# Database
dwe cmd db.cli
dwe cmd db.dump-create
dwe cmd db.dump-deploy
```

Browse the full catalogue with `dwe cmd` (interactive) or `dwe cmd list`.

## Layout & docs

- **`AGENTS.md`** (and the `CLAUDE.md` symlink) — the working guide for this repo's structure.
- **`workspace/`** — all DWE configuration: `defaults.yml`, `services/<name>/service.yml`,
  `commands/`, `templates/`.
- **`dwe docs`** — the authoritative, versioned reference:

> This is a demonstration environment intended for local development only — not hardened for production.
