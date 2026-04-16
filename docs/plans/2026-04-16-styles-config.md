# UI Styles Config + Tables + Status Rewrite

## Overview
- Extract hardcoded Lipgloss colors from `internal/ui/styles.go` into `devbox/styles.yml`
- Move `header` block from `devbox/info.yml` into `styles.yml`
- Fix current UX issues: add newline after ASCII header, remove URL from compact summary
- Rewrite `services list` and `tools list` to use Lipgloss tables (styled, with configurable colors)
- Rewrite `status` command into a full devbox status dashboard: stack health, service/tool tables, topology
- All UI uses shared styles from `styles.yml` and the Charm stack (lipgloss tables, lists)

## Context (from discovery)

### Repositories involved
This plan touches **two separate git repositories**:

1. **`next-laravel/`** (outer repo, current) — config files (`devbox/styles.yml`, `devbox/info.yml`, `CLAUDE.md`), docs, Makefile
   - Current branch: `cli-ux-refactor`
2. **`next-laravel/devbox-cli/`** (inner repo, separate git) — Go source; remote: `github.com/semsemyonoff/devbox-next-cli.git`
   - Current branch: `feat/cli-ux-refactor`
   - **Before starting Task 1**: create branch `feat/styles-config` in `devbox-cli/` (`git -C devbox-cli checkout -b feat/styles-config`)
   - Commit Go changes in `devbox-cli/` as you complete each task
   - Commits in the outer repo cover config/docs changes only

- **Styles:** `internal/ui/styles.go` — 7 hardcoded Lipgloss style vars (lines 15-36)
- **Info dashboard:** `internal/ui/info.go` — renders sections from `devbox/info.yml`
- **Compact summary:** `internal/ui/summary.go` — `RenderSummary()` shows project name, state, URL, counts
- **Header config:** `devbox/info.yml` lines 1-7 — `header.ascii` block (to be moved)
- **Services list:** `internal/command/service.go` lines 72-147 — manual `fmt.Fprintf` column alignment with render ANSI colors
- **Tools list:** `internal/command/tools.go` lines 55-125 — same manual approach
- **Status cmd:** `internal/command/status.go` — delegates to `runServices()` in `services.go` which uses legacy `render.Writer` for a crude topology dump
- **Container check:** `containerRunning()` in `service.go` — calls `docker ps -q --filter`
- **Compose topology:** `compose.yaml` defines nginx→app-main→{db,redis}; overlays add adminer→db, redis-insight→redis, mailpit (standalone), app-second→{db,redis,app-main}
- **Lipgloss table:** Available in `lipgloss v1.1.0` (`table.go` in package root). Also `list` sub-package for tree rendering.
- **Lipgloss list:** Available as `lipgloss/list` for tree/topology rendering
- **Scope boundary:** Only `internal/ui/` styles are configurable. `internal/render/` (plain ANSI for passthrough) stays hardcoded.

## Development Approach
- **Git workflow**: Go changes committed to `devbox-cli/` (its own repo, branch `feat/styles-config`); config/doc changes committed to the outer `next-laravel` repo. Commit after each task completes and tests pass — use `git -C devbox-cli commit` for Go changes, `git commit` for outer repo changes.
- **Testing approach**: Regular (code first, then tests)
- Complete each task fully before moving to the next
- **CRITICAL: every task MUST include new/updated tests**
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- Maintain backward compatibility — omitting `styles.yml` must produce identical output to today

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix

## Technical Details

### styles.yml structure

This project is a Laravel pilot, so the color palette is inspired by Laravel's brand identity:
coral-red (#F05340 → ANSI 203), warm accents, neutral grays. The result is a warm,
red-accented terminal aesthetic that's distinctly Laravel-feeling.

ANSI 256-color reference for the chosen palette:
- `203` (#ff5f5f) — coral red, closest to Laravel brand red #F05340
- `167` (#d75f5f) — darker coral, for section dividers
- `209` (#ff875f) — warm salmon, for subheaders
- `210` (#ff8787) — light coral, for info messages
- `214` (#ffaf00) — amber, for warnings
- `245` (#8a8a8a) — neutral gray, for muted/disabled text
- `2` (#008000) — standard green, for enabled/running status

```yaml
# ASCII art header (moved from info.yml)
# Laravel-inspired: red header for brand recognition
header:
  lines:
    - "Welcome to"
    - "Devbox Next"
  font: doom
  color: red

# UI element colors — ANSI 256-color palette codes
# Palette inspired by Laravel brand identity (coral-red + warm accents + neutral grays)
colors:
  # Definition label text (e.g., "Project", "URL") — Laravel coral red
  label: "203"
  # Section header text (e.g., "── URLs ──") — darker coral for structure
  section_title: "167"
  # Sub-section headers within a section — warm salmon
  subheader: "209"
  # Secondary/muted text (counts, separators, state labels) — neutral gray
  muted: "245"
  # Warning messages — amber
  warning: "214"
  # Informational messages — light coral (Laravel-warm)
  info: "210"

  # Semantic status colors (used in tables/status)
  enabled: "2"           # green — enabled/running/active
  disabled: "245"        # neutral gray — disabled/off
  mandatory: "203"       # Laravel red — mandatory items
  partial: "214"         # amber — partially running / stopped

  # Table colors (shared across all Lipgloss tables) — Laravel red accents
  table_border: "167"    # darker coral — table border lines
  table_header: "203"    # Laravel red — table header text

# Separator character between label and value in definitions
separator: "—"
```

### Config struct

```go
type StylesConfig struct {
    Header    StylesHeader `yaml:"header"`
    Colors    StylesColors `yaml:"colors"`
    Separator string       `yaml:"separator"`
}

type StylesHeader struct {
    Lines []string `yaml:"lines"`
    Font  string   `yaml:"font"`
    Color string   `yaml:"color"`
}

type StylesColors struct {
    // Info dashboard
    Label        string `yaml:"label"`
    SectionTitle string `yaml:"section_title"`
    SubHeader    string `yaml:"subheader"`
    Muted        string `yaml:"muted"`
    Warning      string `yaml:"warning"`
    Info         string `yaml:"info"`
    // Semantic status
    Enabled   string `yaml:"enabled"`
    Disabled  string `yaml:"disabled"`
    Mandatory string `yaml:"mandatory"`
    Partial   string `yaml:"partial"`
    // Table
    TableBorder string `yaml:"table_border"`
    TableHeader string `yaml:"table_header"`
}
```

### Topology approach

The `status` command topology uses `docker compose config` to get the merged compose graph (services + depends_on), then renders a tree using lipgloss/list. Each node shows:
- Service name
- Status indicator (running/stopped/disabled)
- Dependencies as children

Fallback: if `docker compose config` fails (Docker not running), render from config data only (no running status).

**Topology tree example:**
```
Stack: running ●

  nginx (running)
  ├── app-main (running)
  │   ├── db (running)
  │   └── redis (running)
  └── app-second (disabled)
      ├── db (running)
      ├── redis (running)
      └── app-main (running)

  adminer (stopped)
  └── db (running)

  redis-insight (disabled)

  mailpit (disabled)
```

## Implementation Steps

### Task 1: Quick UX fixes — newline after ASCII, remove URL from summary
- [x] Create branch in devbox-cli repo: `git -C devbox-cli checkout -b feat/styles-config`
- [x] In `internal/command/root.go` (or `info.go`): add `\n` after ASCII header output so it doesn't stick to subsequent elements
- [x] In `internal/ui/summary.go`: remove the URL part from `RenderSummary()` (keep project name + state only on line 1)
- [x] Update `summary_test.go` — remove/update URL-related tests
- [x] Run tests — must pass before next task

### Task 2: Add StylesConfig and LoadStylesConfig
- [x] Create `devbox-cli/internal/config/styles.go` with `StylesConfig`, `StylesHeader`, `StylesColors` structs
- [x] Implement `LoadStylesConfig(path string) (*StylesConfig, error)` following `LoadInfoConfig` pattern
- [x] Write tests for `LoadStylesConfig` — valid file, missing file, partial fields
- [x] Run tests — must pass before next task

### Task 3: Create devbox/styles.yml and update info.yml
- [x] Create `devbox/styles.yml` with header block (from info.yml) and color defaults matching current hardcoded values
- [x] Remove `header` block from `devbox/info.yml`
- [x] Update `InfoConfig` struct — remove `Header` field
- [x] Update `LoadInfoConfig` tests to reflect removed header
- [x] Run tests — must pass before next task

### Task 4: Add ApplyStyles to ui package
- [x] Add `ApplyStyles(cfg *config.StylesConfig)` in `internal/ui/styles.go`
- [x] Rebuild all package-level style vars from config colors (skip empty = keep default)
- [x] Change `defSep` from const to var, update from config `Separator`
- [x] Add new style vars for semantic colors: `styleEnabled`, `styleDisabled`, `styleMandatory`, `stylePartial`
- [x] Add new style vars for tables: `styleTableBorder`, `styleTableHeader`
- [x] Write tests: `ApplyStyles` changes output, empty config preserves defaults
- [x] Run tests — must pass before next task

### Task 5: Wire styles loading into commands
- [x] Update `internal/command/root.go` — load `StylesConfig`, call `ApplyStyles`, use `StylesConfig.Header` for ASCII
- [x] Update `internal/command/info.go` — load `StylesConfig`, call `ApplyStyles`, use header from styles
- [x] Graceful handling when `styles.yml` is missing (use defaults, no error)
- [x] Update command tests
- [x] Run tests — must pass before next task

### Task 6: Add Lipgloss table renderer to ui package
- [x] Add `internal/ui/table.go` with helper functions to build Lipgloss tables using shared table styles
- [x] Table helper accepts rows/headers, applies `styleTableBorder`, `styleTableHeader` from styles
- [x] Write tests for table rendering (verify border/header colors are applied)
- [x] Run tests — must pass before next task

### Task 7: Rewrite `services list` to use Lipgloss tables
- [x] Rewrite `runServiceList()` in `internal/command/service.go` to use `ui.RenderServiceTable()` (or similar)
- [x] Table columns: NAME, CONTAINER, STATE, RUNNING — same data, Lipgloss table rendering
- [x] Use semantic style vars (`styleEnabled`, `styleDisabled`, `styleMandatory`) for row colors
- [x] Load and apply styles config before rendering
- [x] Update tests for new output format
- [x] Run tests — must pass before next task

### Task 8: Rewrite `tools list` to use Lipgloss tables
- [x] Rewrite `runToolList()` in `internal/command/tools.go` to use `ui.RenderToolTable()` (or similar)
- [x] Table columns: NAME, HOST, PORT, STATE, RUNNING — same data, Lipgloss table rendering
- [x] Use semantic style vars for row colors
- [x] Load and apply styles config before rendering
- [x] Update tests for new output format
- [x] Run tests — must pass before next task

### Task 9: Rewrite `status` command — stack health + tables
- [x] Rewrite `internal/command/status.go` to show stack running status:
  - All enabled running → green "● running"
  - Some running → yellow "◐ partial"
  - None running → red "○ stopped"
- [x] Show service summary table (reuse `ui.RenderServiceTable` from task 7)
- [x] Show tool summary table (reuse `ui.RenderToolTable` from task 8)
- [x] Load styles config and apply before rendering
- [x] Write tests for status aggregation logic (all/partial/none running)
- [x] Run tests — must pass before next task

### Task 10: Add topology visualization to `status`
- [x] Add `internal/ui/topology.go` — parse compose topology from `docker compose config` output (YAML/JSON)
- [x] Build dependency DAG: map each service to its `depends_on` list
- [x] Render as styled tree using lipgloss (indented tree with box-drawing chars or lipgloss/list)
- [x] Color nodes by status: running (green), stopped (yellow), disabled (gray)
- [x] Integrate into `status` command output (after tables)
- [x] Fallback: if docker not available, show topology from config only (no running status)
- [x] Write tests for DAG building and tree rendering
- [x] Run tests — must pass before next task

### Task 11: Verify acceptance criteria
- [x] Verify: `devbox` (no args) — no URL in summary, newline after ASCII header [manual test - skipped, not automatable]
- [x] Verify: `devbox services list` and `devbox tools list` — styled Lipgloss tables [manual test - skipped, not automatable]
- [x] Verify: `devbox status` — stack health indicator + tables + topology tree [manual test - skipped, not automatable]
- [x] Verify: changing colors in `styles.yml` affects all styled output [manual test - skipped, not automatable]
- [x] Verify: omitting `styles.yml` produces sensible defaults [manual test - skipped, not automatable]
- [x] Run full test suite — all 11 packages pass
- [x] Run linter — 0 issues

### Task 12: [Final] Update documentation
- [ ] Update CLAUDE.md — add `devbox/styles.yml` to project layout, config model, and package descriptions
- [ ] Regenerate reference docs (`./bin/devbox docs generate`)

## Post-Completion

**Manual verification:**
- Run `./bin/devbox` — verify clean spacing after ASCII art, no URL in summary
- Run `./bin/devbox info` — verify styled dashboard with correct colors
- Run `./bin/devbox services list` — verify Lipgloss table with colored rows
- Run `./bin/devbox tools list` — same
- Run `./bin/devbox status` — verify stack health, tables, topology tree
- Edit `devbox/styles.yml` colors and verify changes propagate everywhere
- Delete `devbox/styles.yml` and verify graceful fallback
