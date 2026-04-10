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
7. **Incremental migration** — No big bang rewrite. Four phases, each delivering standalone value while preserving backward compatibility.
8. **Editor-agnostic** — Must support JetBrains, VS Code, and Zed equally via generated configurations.
9. **AI-friendly structure** — Predictable directory layout, declarative entities, safe extensibility. An agent or human should be able to understand the project state by reading config files without tracing Make logic.

## Design principles

### CLI (Go)
- Go is the only language for CLI (cross-platform binary, no runtime dependencies).
- CLI must NOT become a second docker-compose. It computes, renders, and generates — it does not manage containers.
- Keep packages focused: `config` (loading/merging), `render` (ANSI output), `tpl` (templates), `command` (cobra wiring).
- Errors bubble up with `fmt.Errorf` wrapping. Root command catches and renders them via `render.Stdout().Error()`.
- Minimal dependencies. Current set: cobra, yaml.v3, go-figure. Do not add dependencies without strong justification.
- All user-visible output formatting lives in the `render` package. Make recipes must not produce styled output directly — they call CLI print subcommands via macros.

### Config
- Three layers merged in strict order: `devbox.yml` (structure) → `devbox/defaults.yml` (versioned defaults) → `devbox/local.yml` (gitignored user overrides). Later wins, maps merge recursively.
- `devbox.yml` is lean — only project identity and service structure. Runtime details (ports, hosts, tools, state) live in `defaults.yml`.
- Export rules are declarative and live in `defaults.yml` under `exports.env`. Each rule maps a dot-path in the merged config to an env variable name.
- `devbox/local.yml` is always gitignored. `devbox/local.example.yml` is the tracked template showing available overrides.

### Make
- All user-visible output goes through CLI macros: `$(call ok,...)`, `$(call err,...)`, `$(call warn,...)`, `$(call inf,...)`. Defined in `make/macros.mk`.
- Public targets use `snake_case`. Internal targets use `private_*` prefix.
- Use `@` to suppress command echo in recipes.
- Makefile includes `make/macros.mk` for output; future phases will add more `.mk` files for atomic commands.
- Cross-platform: must work on macOS and Linux (including WSL). Prefer portable shell constructs.

### General
- Do not commit secrets to `.env` or config files.
- `legacy/` directory is gitignored and contains old devbox repos for reference only. Do not modify legacy code.
- `devbox-cli/` directory is gitignored (built separately). Binary output goes to `bin/devbox`.
- When adding new functionality, update both the CLI implementation and the relevant config schema/help definitions.

## Architecture

- **devbox-cli** (`devbox-cli/`) — Go binary, the shared core: config loading, rendering, env generation, info display
- **Make** (`Makefile` + `make/`) — thin execution layer, delegates all output to CLI via `make/macros.mk`
- **Config** — 3-layer YAML merge: `devbox.yml` → `devbox/defaults.yml` → `devbox/local.yml` (gitignored)
- `.env` is a **generated artifact** (`devbox render env -o .env`), never a source of truth

## Project layout

```
devbox.yml              # structural spec: project + services
devbox/defaults.yml     # versioned defaults: tools, runtime, ports, hosts, exports
devbox/local.yml        # local overrides (gitignored)
devbox/help.yml         # declarative info/help screen config
Makefile                # thin facade — calls ./bin/devbox
make/macros.mk          # output macros (ok, err, warn, inf) → devbox print
devbox-cli/             # Go module (gitignored, built separately into bin/)
legacy/                 # old devbox repos (gitignored)
```

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
- `internal/config/` — `DevboxConfig` struct, layered `LoadConfig()`, `ResolvePath()` for dot-paths, `ExportRule`
- `internal/render/` — `Writer` with ANSI output methods (Success, Error, Warning, Info, Definition, TableHeader, ASCII art)
- `internal/tpl/` — Go template engine with `Render()`, `EvalCondition()`, custom `FuncMap` (`appURL`)
- `internal/command/` — cobra commands: `info`, `render env`, `print {success,warning,info,error}`

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

`devbox/defaults.yml` — tools, runtime, ports, hosts, export rules (tracked).

`devbox/local.yml` — per-user overrides for state, tools, ports (gitignored). See `devbox/local.example.yml` for options.

## Make macros

All Make output goes through CLI: `$(call ok,msg)`, `$(call err,msg[,exit_code])`, `$(call warn,msg)`, `$(call inf,msg)`. Defined in `make/macros.mk`.

## Migration phases

This repo is a pilot for migrating from the legacy devbox (Make-as-DSL) to a declarative architecture. Each phase delivers standalone value.

1. **Phase 1 — Rendering** (current): Move all output/help/summary from Make macros to CLI. Info display and .env generation work via `devbox info` and `devbox render env`. Make macros delegate to `devbox print`.
2. **Phase 2 — Config Orchestrator**: Merge config layers, compute enabled services/tools, resolve compose overlays, inspect topology — all in CLI. Make calls CLI to get computed values.
3. **Phase 3 — Deploy**: Declarative deploy phases in config. CLI generates deploy plans. Make executes atomic steps from the generated plan.
4. **Phase 4 — Make Refactor**: Split large Make recipes into atomic commands. Make becomes a pure execution layer with no orchestration logic.

### Success criteria

- Help/output independent of Make macros (Phase 1 — done)
- Services/tools computed via devbox-cli
- `.env` generated via export layer (Phase 1 — done)
- Deploy built via generated plan
- Config structure explicit and predictable
- Make thinner and more atomic
- Ready for editor/devcontainer generation layer
