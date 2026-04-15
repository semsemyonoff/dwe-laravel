# Docker Control Plane — devbox docker as the canonical runtime API

## Overview

Refactor the docker compose integration so that `devbox-cli` becomes the single control plane:

- **`devbox docker ...`** — public lifecycle API (up, down, stop, restart, logs, ps, exec, run, wait)
- **`devbox compose ...`** — low-level diagnostic layer (files, argv, raw)
- **`make`** — thin compatibility facade that delegates to `devbox docker ...`
- **`devbox/docker.yml`** + **`devbox/docker.local.yml`** — compose execution policy
- No direct `docker compose` calls in YAML commands or deploy steps

### Problem it solves

Currently the system has three independent paths to docker compose:
1. Makefile assembles `COMPOSE_FILES`, `DOCKER_COMPOSE_FLAGS`, `PROJECT_FULL` and calls `docker compose` directly
2. YAML commands (e.g. `app.install`) hardcode `docker compose` with inline project name and file flags
3. Service runners (ServiceExecRunner/ServiceRunRunner) build compose commands internally

This means compose flags, project naming, and file resolution logic is duplicated in 3+ places. A single `devbox docker` layer unifies all paths.

### Integration with existing system

- Config loading (`LoadConfig`) gains a new `LoadDockerConfig()` for the docker policy layer
- `ComposeFiles()` remains the canonical file list source
- Service runners delegate to the shared docker package instead of building compose commands directly
- Deploy steps use `devbox docker` commands instead of `devbox compose run`

## Context (from discovery)

**Files/components involved:**
- `devbox-cli/internal/command/compose.go` — current compose commands (files, wait, run)
- `devbox-cli/internal/command/root.go` — command registration
- `devbox-cli/internal/config/devbox.go` — ComposeConfig, ComposeFiles(), ProjectConfig
- `devbox-cli/internal/commands/runner_service.go` — ServiceExecRunner, ServiceRunRunner, buildDockerComposeCmd
- `devbox-cli/internal/commands/runner_host.go` — HostRunner, DevboxRunner
- `Makefile` — compose flag assembly and lifecycle targets
- `devbox/commands/app.yml` — direct `docker compose` in app.install
- `devbox/deploy.yml` — uses `devbox: "compose run -- ..."` for lifecycle
- `devbox/deploy/main.yml` — per-service deploy steps
- `devbox-cli/go.mod` — dependencies to update

**Separate git repo:** `devbox-cli/` is its own git repository — changes there need a separate branch and commits.

**Related patterns:**
- `buildDockerComposeCmd()` in runner_service.go is the shared compose command builder
- `DevboxRunner` invokes `$(os.Executable()) <subcommand>` — deploy/commands can call `devbox docker up` through this
- Template interpolation (`${project.prefix}`, `${host.uid}`) in YAML commands

## Development Approach
- **Testing approach**: Regular (code first, then tests)
- Complete each task fully before moving to the next
- Make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
- **CRITICAL: all tests must pass before starting next task** — no exceptions
- **CRITICAL: update this plan file when scope changes during implementation**
- **CRITICAL: `devbox-cli/` is a separate git repo — create branch there and commit changes separately**
- Run `cd devbox-cli && make test && make lint` after every Go code change
- Maintain backward compatibility during transition

## Testing Strategy
- **Unit tests**: required for every task (Go tests in `devbox-cli/`)
- Build: `cd devbox-cli && make build` after structural changes
- Lint: `cd devbox-cli && make lint` after every change

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Update plan if implementation deviates from original scope

## What Goes Where
- **Implementation Steps** (`[ ]` checkboxes): tasks achievable within this codebase
- **Post-Completion** (no checkboxes): items requiring external action

## Implementation Steps

### Task 1: Update Go dependencies
- [x] Update `devbox-cli/go.mod`: cobra → 1.10.2, pflag → 1.0.10
- [x] Run `cd devbox-cli && go mod tidy`
- [x] Run `cd devbox-cli && make build` to verify compilation
- [x] Run tests — must pass before next task
- [x] Run linter — must pass before next task
- [x] Commit in devbox-cli repo

### Task 2: Add docker policy config layer
- [x] Create `devbox/docker.yml` with default compose execution policy:
  ```yaml
  # Docker/Compose execution policy.
  # Loaded separately — not merged with the 3-layer devbox config.
  
  project_name: "${project.prefix}-${project.name}"
  
  args:
    global: ["--ansi", "always", "--progress", "tty"]
    up: ["-d", "--remove-orphans"]
    down: []
    stop: []
    restart: []
    logs: ["-f"]
    ps: []
    exec: []
    run: ["--rm"]
  
  env:
    auto_generate: true           # regenerate .env before lifecycle commands
    commands: [up, run, exec]     # which commands trigger .env generation
  ```
- [x] Create `devbox/docker.local.example.yml` showing override options
- [x] Add `devbox/docker.local.yml` to `.gitignore`
- [x] Add `DockerConfig` struct in `devbox-cli/internal/config/docker.go`:
  - `ProjectName string` (template string, resolved against config)
  - `Args` map with `Global []string` and per-command `[]string`
  - `Env` struct with `AutoGenerate bool`, `Commands []string`
- [x] Add `LoadDockerConfig(baseDir string, cfg *DevboxConfig) (*DockerConfig, error)` — loads `docker.yml`, merges `docker.local.yml`, resolves project name template
- [x] Write tests for DockerConfig loading, merging, and project name resolution
- [x] Run tests and linter — must pass before next task
- [x] Commit in devbox-cli repo

### Task 3: Create internal docker package for compose execution
- [x] Create `devbox-cli/internal/docker/compose.go` with `Compose` struct:
  ```go
  type Compose struct {
      ProjectName string
      Files       []string
      GlobalArgs  []string
      CommandArgs map[string][]string  // per-command default args
  }
  ```
- [x] Add `NewCompose(cfg *config.DevboxConfig, dockerCfg *config.DockerConfig) *Compose`
- [x] Add method `Exec(command string, extraArgs ...string) error` — runs `docker compose` with project name, files, global args, command default args, and extra args; connects stdin/stdout/stderr
- [x] Add method `BuildArgs(command string, extraArgs ...string) []string` — returns the full arg list without executing (for diagnostics / `compose argv`)
- [x] Add method `ContainerIDs() ([]string, error)` — replaces `dockerComposeContainerIDs` from compose.go
- [x] Write tests for BuildArgs (verify correct arg ordering, merging)
- [x] Write tests for NewCompose (correct initialization from config)
- [x] Run tests and linter — must pass before next task
- [x] Commit in devbox-cli repo

### Task 4: Create `devbox docker` command group
- [x] Create `devbox-cli/internal/command/docker.go` with `newDockerCmd(flags)`:
  - `devbox docker up [services...]` — runs compose up with policy args
  - `devbox docker down` — runs compose down with policy args
  - `devbox docker stop [services...]` — runs compose stop
  - `devbox docker restart [services...]` — runs compose restart
  - `devbox docker logs [services...]` — runs compose logs with policy args
  - `devbox docker ps` — runs compose ps
  - `devbox docker exec <service> [-- cmd...]` — runs compose exec
  - `devbox docker run <service> [-- cmd...]` — runs compose run
  - `devbox docker wait` — migrated from compose wait (polls health)
- [x] Each command follows the pipeline: load config → load docker policy → build Compose → optionally generate .env → execute
- [x] `.env` auto-generation: if `dockerCfg.Env.AutoGenerate` and command is in `Env.Commands`, call `devbox render env -o .env` before executing
- [x] Register `newDockerCmd(flags)` in `root.go`
- [x] Write tests for docker command argument assembly
- [x] Run tests and linter — must pass before next task
- [x] Commit in devbox-cli repo

### Task 5: Refactor `devbox compose` to low-level diagnostic layer
- [x] Keep `devbox compose files` — unchanged
- [x] Rename `devbox compose run` → `devbox compose raw` (escape hatch for direct passthrough)
- [x] Add `devbox compose argv <command> [args...]` — shows the full `docker compose` command that `devbox docker <command>` would execute, without running it
- [x] Remove `devbox compose wait` (moved to `devbox docker wait`)
- [x] Update `compose.go` to use the `docker` package for arg building
- [x] Write tests for compose argv output
- [x] Run tests and linter — must pass before next task
- [x] Commit in devbox-cli repo

### Task 6: Refactor service runners to use docker package
- [x] Update `buildDockerComposeCmd()` in `runner_service.go` to accept a `*docker.Compose` (or build one from config) instead of assembling compose args manually
- [x] Update `isContainerRunning()` to use the docker package
- [x] Update `ServiceExecRunner.BuildCommand()` and `ServiceRunRunner.BuildCommand()` to use the shared Compose struct for project name and file list
- [x] Ensure compose global args from docker policy are applied to service commands
- [x] Update existing tests for service runners
- [x] Write tests for the refactored command building
- [x] Run tests and linter — must pass before next task
- [x] Commit in devbox-cli repo

### Task 7: Remove direct `docker compose` from YAML commands
- [x] Update `devbox/commands/app.yml`: change `app.install` from `type: command` with direct `docker compose` to use `devbox docker run` or a new appropriate mechanism (e.g. `type: devbox` with `run: "docker run ..."` or add installer support to docker commands)
- [x] Verify all files in `devbox/commands/` have no direct `docker compose` references
- [x] Commit in next-laravel repo

### Task 8: Update deploy steps to use `devbox docker`
- [x] Update `devbox/deploy.yml`:
  - `devbox: "compose run -- --ansi always --progress tty up -d --remove-orphans"` → `devbox: "docker up"`
  - `devbox: "compose wait"` → `devbox: "docker wait"`
- [x] Verify `devbox/deploy/main.yml` and `devbox/deploy/second.yml` have no direct compose calls (they use `command:` references — should be fine)
- [x] Commit in next-laravel repo

### Task 9: Simplify Makefile to pure delegation
- [x] Remove `COMPOSE_FILES`, `DOCKER_COMPOSE_FLAGS`, `DOCKER_COMPOSE`, `PROJECT_PREFIX`, `PROJECT_NAME`, `PROJECT_FULL` variables
- [x] Rewrite lifecycle targets as pure delegation:
  ```makefile
  up: private_ensure_composer_cache
  	@$(DEVBOX_BIN) docker up
  
  down:
  	@$(DEVBOX_BIN) docker down
  
  stop:
  	@$(DEVBOX_BIN) docker stop
  
  restart:
  	@$(DEVBOX_BIN) docker restart
  
  logs:
  	@$(DEVBOX_BIN) docker logs
  ```
- [x] Keep `deploy`, `deploy-plan`, `deploy-reset`, `cli`, `cli-root`, `help`, `env` — they already delegate to devbox CLI
- [x] Update `deploy-reset` to use `devbox docker down` and resolve project name via CLI (e.g. `$(shell $(DEVBOX_BIN) compose project-name)` or inline)
- [x] Update `private_ensure_composer_cache` — keep as is (it's a Docker volume check, not compose)
- [x] Commit in next-laravel repo

### Task 10: Update CLAUDE.md and project documentation
- [x] Update CLAUDE.md: document `devbox docker` as the primary runtime API
- [x] Update CLAUDE.md: document `devbox compose` as low-level/diagnostic
- [x] Update CLAUDE.md: document `devbox/docker.yml` + `devbox/docker.local.yml`
- [x] Update project layout section in CLAUDE.md
- [x] Update Makefile section in CLAUDE.md (no more compose flag assembly)

### Task 11: Verify acceptance criteria
- [x] Verify all requirements from Overview are implemented
- [x] Verify `devbox docker up/down/stop/restart/logs/ps/exec/run/wait` all work
- [x] Verify `devbox compose files` still works
- [x] Verify `devbox compose argv up` shows correct command
- [x] Verify `devbox compose raw -- ps` works as escape hatch
- [x] Verify `make up/down/stop/restart/logs` delegate to `devbox docker`
- [x] Verify no direct `docker compose` in `devbox/commands/*.yml`
- [x] Verify no direct `docker compose` in `devbox/deploy*.yml`
- [x] Run full test suite: `cd devbox-cli && make test`
- [x] Run linter: `cd devbox-cli && make lint`

### Task 12: [Final] Update documentation
- [x] Update README.md if needed (no project-root README exists; CLAUDE.md already comprehensive)
- [x] Update project knowledge docs if new patterns discovered (updated memory docs to reflect Phase 5 completion)

## Technical Details

### Docker policy config schema (`devbox/docker.yml`)

```yaml
project_name: "${project.prefix}-${project.name}"

args:
  global: ["--ansi", "always", "--progress", "tty"]
  up: ["-d", "--remove-orphans"]
  down: []
  stop: []
  restart: []
  logs: ["-f"]
  ps: []
  exec: []
  run: ["--rm"]

env:
  auto_generate: true
  commands: [up, run, exec]
```

### Compose command construction pipeline

```
devbox docker up [redis]
  ↓
Load devbox config (3-layer merge)
  ↓
Load docker policy (docker.yml + docker.local.yml)
  ↓
Resolve project name from template
  ↓
Compute compose file list via ComposeFiles()
  ↓
If auto_generate && "up" in env.commands → render .env
  ↓
Build argv:
  docker compose
    -p <project-name>
    -f compose.yaml -f compose/tools/adminer.yml ...
    --ansi always --progress tty        ← global args
    up
    -d --remove-orphans                 ← command default args
    redis                               ← user extra args
  ↓
exec.Command("docker", argv...)
```

### `devbox docker` vs `devbox compose` split

| Command | Layer | Purpose |
|---------|-------|---------|
| `devbox docker up/down/stop/restart` | Public | Lifecycle management |
| `devbox docker logs/ps` | Public | Monitoring |
| `devbox docker exec/run` | Public | Container interaction |
| `devbox docker wait` | Public | Health polling |
| `devbox compose files` | Diagnostic | Show resolved file list |
| `devbox compose argv <cmd>` | Diagnostic | Show what docker command would run |
| `devbox compose raw -- <args>` | Escape hatch | Direct passthrough to docker compose |

### Service runner refactoring

Before:
```go
func buildDockerComposeCmd(...) *exec.Cmd {
    // manually assembles -p, -f flags, exec/run subcommand, user/workdir/env
}
```

After:
```go
func buildDockerComposeCmd(compose *docker.Compose, ...) *exec.Cmd {
    // uses compose.Files, compose.ProjectName for -p, -f
    // still handles exec/run specific flags (user, workdir, env)
}
```

### app.install migration

Before (direct docker compose):
```yaml
install:
  type: command
  run: "docker compose --progress tty -p ${project.prefix}-${project.name} -f compose/installer.yml run --rm --quiet-pull -u ${host.uid}:${host.gid} app-install"
```

After (devbox docker or devbox runner):
```yaml
install:
  type: devbox
  run: "docker run --quiet-pull -u ${host.uid}:${host.gid} -f compose/installer.yml app-install"
```
Note: exact syntax TBD during implementation — the key constraint is that the installer uses a separate compose file (`compose/installer.yml`) not in the regular overlay list.

## Post-Completion

**Manual verification:**
- Run `make deploy` end-to-end and verify all phases complete successfully
- Run `make up`, `make down`, `make logs` and verify they work identically to before
- Verify `devbox docker exec app-main -- php artisan --version` works
- Test with `devbox/docker.local.yml` overrides (e.g. change global args)
