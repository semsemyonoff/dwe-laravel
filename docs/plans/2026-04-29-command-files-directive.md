# Command Files Directive

## Overview

Extend the declarative command system with a top-level `files:` directive that lets commands declare external file artefacts they read or produce. The CLI resolves paths (with template rendering, candidate fallback, glob+match+sort, mkdir, overwrite, on_error cleanup that only removes files this invocation actually created), exposes the resolved paths as env vars and template values, and only then dispatches to the regular runner. This pulls file lifecycle out of shell scripts into YAML so the same fallback logic (e.g. `db_2026-04-29.sql.gz → db.sql.gz`) is reusable across all commands and command types.

The plan also lands two unblocking CLI features needed by the dump-deploy workflow: a confirmation-bypass switch on `devbox commands run` (so a script can call `db.drop` non-interactively), plus an explicit verification that `devbox docker exec/run` forwards the `--` separator correctly to `docker compose`.

The first concrete consumers are two Laravel-pilot commands — `db.dump-create` (write) and `db.dump-deploy` (read with candidates fallback) — driving real database dumps via `mariadb-dump` / `mariadb` over `devbox docker exec`. Scripts will use a new `$DEVBOX_BIN` contract variable instead of shelling out to `docker compose` directly.

## Context (from discovery)

- **Two repos**: changes split across `next-laravel/` (pilot, branch `commands`) and `devbox-cli/` (Go CLI core, branch `commands`). devbox-cli is gitignored from the pilot repo and committed independently.
- **Files affected — devbox-cli (Go core)**:
  - `internal/commands/types.go` — add `FileSpec`, `FileCandidate`, `FileAccess`, attach `Files map[string]FileSpec` to `CommandDef`, validation (incl. identifier-safe file IDs)
  - `internal/commands/resolve.go` — add `ResolveFiles()` (split into `ComputeFilePaths` pre-confirm + `PrepareFileEffects` post-confirm); update `BuildEnv` to merge file env vars and detect conflicts
  - `internal/commands/runner.go` — wire file path computation before `ConfirmCommand`, file effects after confirm, on_error cleanup that only removes files newly created this invocation
  - `internal/commands/runner_script.go` — add `DEVBOX_BIN`, `DEVBOX_FILES_JSON` to script contract
  - `internal/command/command_cmd.go` — add `--yes` / `-y` flag to `devbox commands run` that sets `RunContext.SkipConfirm` and propagates `DEVBOX_NONINTERACTIVE=1` to subprocess env
  - `internal/tpl/funcs.go` — add `date`, `datetime`, `base`, `dir` template funcs
  - `internal/tpl/render_command.go` — add `files` namespace to `CompileVarSyntax`; add `Files map[string]ResolvedFile` to `RenderContext` (DTO defined in `tpl` package; see Tech Details)
  - tests for each (`*_test.go`)
  - `docs/reference/commands/` and `docs/reference/cli/` (regenerated via `devbox docs generate`)
- **Files affected — pilot repo**:
  - `devbox/commands/db.yml` — append `dump-create` and `dump-deploy` command definitions
  - `devbox/scripts/db/dump-create.sh` (new)
  - `devbox/scripts/db/dump-deploy.sh` (new)
  - `CLAUDE.md` — extend "Config model" / "Deploy pipeline" sections briefly to mention `files:` and new template funcs
- **Patterns reused**:
  - Same template machinery (`tpl.RenderCommand`, `CompileVarSyntax`) used for params/env/context
  - Existing env-injection layering in `BuildEnv` (`runner.go:124`)
  - Script contract env in `runner_script.go:110`
- **Decisions captured (from clarifications)**:
  - `access: read_write` = read semantics for resolution (file must exist via path or candidates) + script is permitted to modify it; `on_error: remove` does **not** delete the file in `read_write` mode (the file pre-existed by definition) — see Tech Details
  - `files.*` exposed in template context as `${files.<id>.path}` for use in `env:`, `messages:`, `run:`, `cwd:`, **and `confirmation_text`** — path computation (template render only) runs *before* `ConfirmCommand`; mutating effects (mkdir, overwrite check, existed_before bookkeeping) run *after* confirmation
  - File ID grammar: `[a-zA-Z_][a-zA-Z0-9_]*` (no hyphens) so the existing `${...}` regex resolves them; validated at load time

## Development Approach

- **Testing approach**: Regular (code first, then tests within the same task)
- Complete each task fully before moving to the next
- Make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
- **CRITICAL: all tests must pass before starting next task** — `cd devbox-cli && make test && make lint`
- **CRITICAL: commits live in the correct repo**:
  - CLI changes → commits inside `devbox-cli/` (separate git repo, branch `commands`)
  - Pilot YAML/scripts/docs → commits in `next-laravel/` (branch `commands`)
  - Coordinate by completing CLI task, building `bin/devbox`, then exercising from the pilot
- Update plan checkboxes immediately when tasks complete
- Maintain backward compatibility: commands without a `files:` block must behave exactly as today

## Testing Strategy

- **Unit tests** (Go, in `devbox-cli/`):
  - validation: malformed `FileSpec` (missing access, conflicting path/candidates, env conflicts, unknown sort, etc.)
  - resolution read-mode: single path hit, single path miss + required → error, candidates with glob+match+sort picking the right file, all candidates miss + required → error
  - resolution write-mode: path renders, mkdir creates parents, overwrite=false on existing file → error, on_error=remove deletes after failed run
  - env injection: file env vars merged correctly, conflict with `env:`/`params.env`/`context.env` rejected at validation
  - template funcs: `date`/`datetime` formats, `base`/`dir` correctness; `${files.id.path}` substitution
  - script contract: `DEVBOX_BIN` set to current binary path, `DEVBOX_FILES_JSON` shape
- **End-to-end (manual via pilot)**:
  - `devbox commands run db.dump-create` produces `services/main/runtime/dumps/<db>_YYYY-MM-DD.sql.gz`
  - `devbox commands run db.dump-deploy` finds the most recent dated dump and restores it
  - on_error cleanup: simulate failure mid-dump, confirm partial file is removed
- Project does **not** have UI/Playwright tests — skip that strategy.

## Progress Tracking

- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Update plan if implementation deviates from original scope

## Implementation Steps

### Task 1: Add `FileSpec` types and validation (devbox-cli)
- [x] in `internal/commands/types.go`: add `FileAccess` const block (`read`, `write`, `read_write`), `FileSort` consts (`name_asc`, `name_desc`, `modtime_asc`, `modtime_desc`), `FileOnError` consts (`keep`, `remove`)
- [x] add `FileCandidate` struct (`Path`, `Glob`, `Match`, `Sort`)
- [x] add `FileSpec` struct (`Access`, `Path`, `Candidates`, `Required`, `Mkdir`, `Overwrite`, `OnError`, `Env`)
- [x] add `Files map[string]FileSpec` field to `CommandDef`
- [x] extend `CommandDef.Validate()` to call new `validateFiles()`:
    - file-ID grammar: must match `^[a-zA-Z_][a-zA-Z0-9_]*$` (no hyphens; required so the `${files.<id>.path}` regex resolves)
    - per-spec: access required and ∈ {read, write, read_write}
    - presence shape:
        - `write` requires `path`; `candidates` is **rejected** for write mode (write semantics are deterministic — there is no "fallback" target to write to)
        - `read` and `read_write` accept exactly one of `path` xor `candidates`
    - within a candidate: `path` xor `glob`; `match`/`sort` only valid with `glob`; sort value (if set) ∈ enum
    - `mkdir` / `overwrite` only valid for `write`; `on_error` valid for `write` and `read_write` (no-op in `read_write` per safe-cleanup contract, but accepted for declarative consistency)
    - `env` (when set) must be a valid POSIX env name `^[A-Z_][A-Z0-9_]*$`
    - cross-field env-conflict: union of `Env` keys, `Params[*].Env`, `Context[*].Env`, and `Files[*].Env` must be unique; conflict reported with both sources named
- [x] **`Required` field stays a plain `bool`** in `FileSpec` (no `*bool`, no custom unmarshal). `read_write` mode does **not** distinguish "omitted" from "explicit false" at YAML level — instead, the resolver in Task 4 enforces presence as a runtime invariant: read_write **always** treats the file as required, regardless of what `required:` says in the YAML. This avoids adding pointer semantics for one validation rule. Document this in the FileSpec doc comment so users understand `required:` is a no-op for read_write
- [x] write tests in `types_test.go` covering all validation branches (success + each failure mode, including: hyphen file-id rejection; `write` + `candidates` rejected; both `read_write` + `required: true` and `read_write` + `required: false` accepted at validation time — runtime presence enforcement is tested in Task 4)
- [x] `cd devbox-cli && make test && make lint` — must pass before next task

### Task 2: Add template funcs `date`, `datetime`, `base`, `dir` (devbox-cli)
- [x] in `internal/tpl/funcs.go`: register `date` (returns `time.Now().Format("2006-01-02")`), `datetime` (returns `time.Now().Format("2006-01-02_15-04-05")`), `base` (wraps **`filepath.Base`**), `dir` (wraps **`filepath.Dir`**) — chosen over `path.Base`/`path.Dir` because these are filesystem operations on local paths; `filepath` handles OS-specific separators correctly while `path` is for forward-slash URLs/embedded resources
- [x] use `time.Now()` via injectable clock for tests: `var nowFn = time.Now`
- [x] update `commandFuncMap` in `render_command.go` to include the new funcs (already inherited via `FuncMap()` — just confirm)
- [x] add table-driven tests in `engine_test.go` (or new `funcs_test.go`) for each new func, including a clock-stub for `date`/`datetime`; assert `base("/a/b/c.txt") == "c.txt"` and `dir("/a/b/c.txt") == "/a/b"`
- [x] `cd devbox-cli && make test && make lint` — must pass before next task

### Task 3: Expose `files` namespace in template context (devbox-cli)
- [x] in `internal/tpl/render_command.go`: define `ResolvedFile struct { Path string }` as a tiny DTO local to the `tpl` package (chosen over `map[string]map[string]any` for type safety and to avoid an import cycle from `tpl` → `commands`); add `Files map[string]ResolvedFile` to `RenderContext`
- [x] extend `CompileVarSyntax` to handle `${files.<id>.path}` → `{{ resolveFile .Files "<id>" "path" }}`; register `resolveFile` helper in `commandFuncMap`
- [x] write tests in `render_command_test.go`: `${files.dump.path}` resolves to the path; missing id → empty string; unknown subkey → empty string; `${files.foo-bar.path}` is left literal (regex doesn't match — exercises the file-id validation contract from Task 1)
- [x] `cd devbox-cli && make test && make lint` — must pass before next task

### Task 4: Implement `ComputeFilePaths` (pre-confirm, non-mutating) for read/read_write (devbox-cli)
- [x] new file `internal/commands/resolve_files.go`: `ComputeFilePaths(ctx RunContext) (map[string]tpl.ResolvedFile, error)` — pure function, no filesystem mutation, returns map of file id → resolved path
- [x] **path-resolution contract** (applies to every rendered `path` / candidate `path` / candidate `glob`): if the rendered string is **not absolute** (`!filepath.IsAbs`), resolve it against an effective root, then `filepath.Clean` the result. Effective root resolution: `ctx.ProjectRoot` if non-empty, else `os.Getwd()` (matches `runner_script.go:79-85` so programmatic callers with an empty `ProjectRoot` still work). The path stored in `tpl.ResolvedFile.Path` and exposed as `${files.<id>.path}` and the `env:` injected variable is always the **normalized absolute path**. Add a helper `resolveRelative(projectRoot, p string) (string, error)` shared by Compute and Prepare phases; the helper handles the empty-root fallback and surfaces `os.Getwd` errors
- [x] read / read_write logic (mutually identical for path discovery): render `path` template; if set, normalize via the helper above, stat and use; else iterate `candidates` in order; for each candidate render either `path` or `glob` (both normalized via the helper); for glob, expand via `filepath.Glob`, filter basenames by compiled `match` regex (rendered template, applied to the basename, not the full path), sort by chosen mode, pick first; **a missing `candidates[i].path` (stat fails with `os.ErrNotExist`) or an empty glob match is not an error — fall through to `candidates[i+1]`**; only when *all* candidates miss AND the spec requires presence does the function return an error; if all miss and presence is not required, omit id from result. Non-`os.ErrNotExist` errors (e.g. permission denied, invalid regex) abort immediately and are reported with the candidate index
- [x] presence rule: read mode → presence required only when `required: true`; **read_write mode → presence is always required** (file must pre-exist), regardless of `required` (see Task 1 validation)
- [x] write mode: render `path`, no filesystem checks at this stage (existence check + mkdir happen in Task 5's `PrepareFileEffects`)
- [x] write tests in `resolve_files_test.go` using `t.TempDir()`: single-path hit, single-path miss + required, candidates glob+match+sort variants (all four sort modes), match-regex filtering, all-miss + required, all-miss + optional, write-mode returns rendered path without touching disk; **relative path "subdir/x.txt" with `ProjectRoot=/abs/root` resolves to `/abs/root/subdir/x.txt` in the result**; absolute path "/tmp/x.txt" passes through unchanged; **relative path "subdir/x.txt" with `ProjectRoot=""` resolves against `os.Getwd()`** (use `t.Chdir(tempDir)` to assert this deterministically); `read_write` mode + missing file always errors regardless of the `required` field value
- [x] `cd devbox-cli && make test && make lint` — must pass before next task

### Task 5: Implement `PrepareFileEffects` (post-confirm, mutating) + safe on_error cleanup (devbox-cli)
- [x] in `resolve_files.go`: add `PrepareFileEffects(ctx RunContext, paths map[string]tpl.ResolvedFile) (cleanups []func(), err error)`:
    - for **write** entries with `mkdir: true`: `os.MkdirAll(filepath.Dir(path), 0o755)` (validation in Task 1 already rejects `mkdir` for read/read_write, so no branch is needed)
    - for write entries: stat the path; if exists and `overwrite: false` → return error before running runner; record `existedBefore: true|false`
    - for read_write entries: existence already required by ComputeFilePaths; record `existedBefore: true` always (used by the cleanup-suppression rule below)
    - cleanup callback for `on_error: remove` is registered **only when `existedBefore == false`** (file was created by this invocation) — this prevents wiping yesterday's dump when today's `dump-create` fails on an existing target; consequence: `read_write` never registers a cleanup (existedBefore is always true)
    - cleanup callback signature `func()` removes the file via `os.Remove`; errors logged to stderr only
- [x] in `internal/commands/runner.go`: rewire `RunCommand`:
    1. **defensive init**: if `ctx.Render == nil`, allocate `ctx.Render = &tpl.RenderContext{}` (programmatic test callers today pass nil — this keeps them working before any `${...}` is rendered or `Files` is assigned). If `ctx.Render.Raw == nil` and `ctx.Config != nil`, set `ctx.Render.Raw = ctx.Config.Raw`. Initialize `ctx.Render.Params`/`ctx.Render.Context` to empty maps if nil. Document this as the canonical entry-point invariant
    2. `paths, err := ComputeFilePaths(ctx)` — non-mutating
    3. assign `ctx.Render.Files = paths` so confirmation_text + run/cwd/env templates can reference them
    4. `ConfirmCommand(ctx)` (uses `${files.*}` if any)
    5. `cleanups, err := PrepareFileEffects(ctx, paths)`
    6. dispatch via `NewRunner` + `Run`
    7. on runner error: invoke `cleanups` in LIFO order, then propagate
    8. on success: skip cleanups; emit success message
- [x] add a regression test in `runner_test.go` (or wherever `RunCommand` is unit-tested): pass `RunContext{Render: nil, Cmd: <minimal command without files>}` and assert no nil-pointer panic; behavior matches the `Render` set explicitly to a zero `RenderContext`
- [x] write tests in `resolve_files_test.go`:
    - mkdir creates parent
    - overwrite=false + existing file → pre-run error (runner not invoked)
    - overwrite=true + existing file: runner runs, simulated failure → existing file is **preserved** (existedBefore=true)
    - overwrite=true + non-existing file: simulated failure → file is removed (existedBefore=false, on_error=remove)
    - on_error=keep + non-existing file + failure → file left in place
    - read_write + on_error=remove + failure → file preserved
- [x] `cd devbox-cli && make test && make lint` — must pass before next task

### Task 6: Inject file env vars + conflict guard (devbox-cli)

**Signature change**: `BuildEnv` becomes error-returning to surface the runtime conflict guard. All callers update.

- [x] in `internal/commands/resolve.go`: change `func BuildEnv(cmd *CommandDef, params, ctx map[string]any) map[string]string` to `func BuildEnv(cmd *CommandDef, params, ctx map[string]any, files map[string]tpl.ResolvedFile) (map[string]string, error)`; merge order: context-env → params-env → files-env (`spec.Env → resolved.Path`) → command-level `env:` (templates rendered later)
- [x] add runtime conflict guard: if a name is set twice anywhere in the merge, return `fmt.Errorf("env conflict: %q declared by %s and %s", ...)`. This is defensive — Task 1 validation already rejects such conflicts at load — but guards against programmatic constructions in tests
- [x] update **all** call sites to the new signature:
    - `internal/commands/runner_host.go` — `buildRenderedEnv` (line ~139), pass `ctx.Render.Files` and propagate the new error
    - `internal/commands/runner_host.go:41` — direct `BuildEnv` call in `HostRunner.Run`
    - `internal/commands/runner_host.go:111` — direct `BuildEnv` call in `DevboxRunner.Run`
    - `internal/commands/runner_service.go:36` and `:86` — `ServiceExecRunner` and `ServiceRunRunner` calls
    - `internal/commands/runner_script.go:133` — `ScriptRunner.execScript`
    - any test that calls `BuildEnv` directly (search: `BuildEnv\(`)
- [x] thread the resolved files map through `RunContext` (Task 5 already adds `ctx.Render.Files`; this task makes `BuildEnv` consume it from the same source via `buildRenderedEnv`)
- [x] write tests in `resolve_test.go`:
    - file env appears in BuildEnv output with correct path value
    - conflict between `files[*].env` and `params[*].env` returns the documented error
    - conflict between `files[*].env` and command-level `env:` returns error
    - empty files map → BuildEnv behaves identically to today (regression)
- [x] `cd devbox-cli && make test && make lint` — must pass before next task

### Task 7: Extend script contract with `DEVBOX_BIN` and `DEVBOX_FILES_JSON` (devbox-cli)
- [x] in `runner_script.go.buildContractEnv`: resolve `DEVBOX_BIN` via `os.Executable()` (fallback to `os.Args[0]` absolute on error)
- [x] add `DEVBOX_FILES_JSON` containing JSON object `{"<id>": {"path": "..."}}`; empty `{}` when no files declared
- [x] update top-of-file doc comment listing contract env vars
- [x] write tests in `runner_script_test.go`: contract env contains `DEVBOX_BIN` (non-empty, exists), `DEVBOX_FILES_JSON` shape with and without files
- [x] `cd devbox-cli && make test && make lint` — must pass before next task

### Task 8: Loader + integration tests (devbox-cli)
- [x] verify `loader.go` round-trips `Files` correctly (YAML unmarshal into the new struct); add a fixture in `testdata/` if a tests-specific file is missing
- [x] write `runner_script_test.go` integration test: small YAML defining `files: { dump: { access: write, path: "{tmp}/x.txt", env: F } }`; run a script that writes `hello` to `$F`; assert file exists with right content
- [x] write integration test for read-mode: pre-create a file in tempdir, glob+match+sort selects newest, env points at it
- [x] write integration test for on_error: write-mode with on_error=remove + a script that exits 1 → file removed
- [x] `cd devbox-cli && make test && make lint` — must pass before next task

### Task 9: Add confirmation-bypass to `devbox commands run` (devbox-cli)

CLAUDE.md describes a "four-way dispatch" for confirmation but the current code only implements three of the four — neither `RunContext.SkipConfirm` nor a `ConfirmFunc` field exists. This task adds the missing tier and makes it bypassable end-to-end (top-level command + nested workflow steps + nested `devbox commands run` invocations from scripts).

- [x] in `internal/commands/runner.go`: add two fields to `RunContext` — `SkipConfirm bool` (skips command-level confirmation entirely) and `NonInteractive bool` (forces non-interactive code paths regardless of TTY); document both in the struct doc comment
- [x] in `internal/commands/confirmation.go`: at the top of `ConfirmCommand`, after the `nil` / `!Confirmation` early return, add `if ctx.SkipConfirm { return nil }`
- [x] in `internal/commands/runner_workflow.go`: make `isNonInteractive()` honor `RunContext.NonInteractive` (read from the surrounding context, not just `os.Getenv`); when constructing sub-`RunContext` for each workflow step, copy `SkipConfirm` and `NonInteractive` so nested confirms also skip
- [x] in `internal/commands/runner_script.go.buildContractEnv`: when `ctx.NonInteractive` is true, force `DEVBOX_NONINTERACTIVE=1` in the contract env so child `devbox commands run` invocations inherit the bypass via `os.Getenv` (current logic only reads `os.Getenv`, which works for inherited subprocesses but misses programmatic callers)
- [x] in `internal/command/command_cmd.go`: add `--yes` / `-y` boolean flag to `commands run`; when set, populate `RunContext.SkipConfirm = true` and `RunContext.NonInteractive = true`; help text: "Skip confirmation prompts; intended for non-interactive use such as scripts and nested command runs."
- [x] in `internal/command/command_cmd.go` (same entry point): also map the **inherited** `DEVBOX_NONINTERACTIVE=1` env var into `RunContext.SkipConfirm = true` and `RunContext.NonInteractive = true`. Without this mapping, a parent's `DEVBOX_NONINTERACTIVE` would only suppress workflow `confirm:` steps (which already check the env directly) but would still allow command-level `Confirmation: true` to prompt at the top level of a nested call. With the mapping, deep nesting (parent `--yes` → script → nested `commands run`) reliably stays non-interactive without each script needing its own `--yes`
- [x] write tests:
    - confirmation_test.go: `ConfirmCommand` with `SkipConfirm=true` returns nil even when `Confirmation: true` (no prompt issued, no stdin read)
    - runner_workflow_test.go: workflow step inheriting `NonInteractive=true` does not prompt for `confirm:` steps; existing `TestWorkflowRunner_ConfirmStep_NonInteractive_AutoSkip` continues to pass
    - runner_script_test.go: with `RunContext.NonInteractive=true`, contract env contains `DEVBOX_NONINTERACTIVE=1` even when the host env does not
    - command_cmd_test.go: verify --yes flag exists and has correct type
- [x] (cross-reference: Task 13's `dump-deploy.sh` will use `$DEVBOX_BIN commands run db.drop --set database="$TARGET_DB_NAME" --yes`)
- [x] `cd devbox-cli && make test && make lint` — all tests pass

### Task 10: Verify `--` separator handling for `devbox docker exec/run` (devbox-cli)
- [x] read `internal/docker/compose.go` and confirm `BuildArgs` forwards `--` verbatim to `docker compose` (existing test at `compose_test.go:217` shows `exec app-main -- php artisan --version` works — keep / extend that test as a regression guard for `run` as well)
- [x] `internal/command/docker.go`: confirm the `exec` and `run` cobra commands forward args verbatim. Specifically: their cobra args policy must be `cobra.ArbitraryArgs` (or DisableFlagParsing for the user-supplied tail), and arguments after `--` must be carried through via `cmd.ArgsLenAtDash()` so `--` is forwarded into compose's argv, not consumed by cobra's parser
- [x] add **argv-construction unit tests** (no Docker, no subprocess) around the helpers that build the final argv for `docker exec` and `docker run` (e.g. `BuildArgs`, plus the cobra-command argv-assembly function — typically a `newDockerExecCmd`/`runDockerExec` style internal helper; if no such testable seam exists, extract one in this task). Assert: `exec <svc> -- mariadb -u user -- foo` produces argv where `--` appears between `<svc>` and `mariadb` and the user flags after `mariadb` are preserved
- [x] document the contract in a short comment above the `exec` and `run` cobra command definitions
- [x] live `docker compose` execution stays as **manual smoke** (Task 13's manual smoke step exercises the real path); CI must not depend on Docker being available for this verification
- [x] `cd devbox-cli && make test && make lint` — must pass before next task

### Task 11: Build CLI + commit devbox-cli changes
- [ ] `cd devbox-cli && make build` — produces `../bin/devbox`
- [ ] regenerate command reference docs: `./bin/devbox docs generate` (run from pilot repo root)
- [ ] inside `devbox-cli/`: stage and commit (`feat: add files: directive to commands; add --yes flag to commands run; add date/datetime/base/dir tpl funcs; add DEVBOX_BIN/DEVBOX_FILES_JSON script contract`)
- [ ] commit message must mention: spec rationale (artefact lifecycle in YAML), backward compatibility, safe-cleanup semantics (existed_before), and tests added

### Task 12: Pilot — `dump-create` command and script
- [ ] in `devbox/commands/db.yml`: add `dump-create` command (type=script) with `params` (`database` default_from `db.database`, `dump_dir` default_from `db.backup_dir`, `dump_date` bool default true), `env: { DB_NAME: "${param.database}", DB_USER: "${db.user}", DB_PASSWORD: "${db.password}" }` (mirrors the existing `db.create`/`db.drop` env contract — `mariadb-dump` needs auth), `files.dump` (write, templated path with `{{ if .Params.dump_date }}_{{ date }}{{ end }}`, mkdir true, overwrite true, on_error remove, env DUMP_FILE), `script.path: devbox/scripts/db/dump-create.sh`
- [ ] new `devbox/scripts/db/dump-create.sh` — `set -eu`; uses `MYSQL_PWD="$DB_PASSWORD" "$DEVBOX_BIN" docker exec -T db -- mariadb-dump -u"$DB_USER" "$DB_NAME" | gzip > "$DUMP_FILE"` (mirrors the `MYSQL_PWD` pattern already used by other db commands in the repo)
- [ ] add a `db.backup_dir` entry to `devbox/defaults.yml` if not already present (e.g. `services/main/runtime/dumps`)
- [ ] manual smoke: `./bin/devbox commands run db.dump-create` and verify file appears in `services/main/runtime/dumps/`
- [ ] inside `devbox-cli`: add a YAML **fixture** under `internal/commands/testdata/files_dump_create.yml` mirroring the dump-create shape, with literal `params.*.default` values (not `default_from`) and an `env:` block that references `${files.dump.path}`, `${param.database}`, and `${db.user}` so the test exercises the full render pipeline (params + context + files + Raw config). Pair it with a fixture `Raw` config in the test (e.g. `map[string]any{"db": {"user": "root", "password": "secret"}}`) and assert:
    - YAML parses and validates (no errors, no warnings)
    - `BuildEnv` (after Task 6's signature change) returns env containing `DUMP_FILE=<absolute path>`, `DB_NAME=<database>`, and `${db.user}` rendered to "root"
    - env-conflict guard fires when a `params[*].env: DUMP_FILE` is added to the fixture
- [ ] **Do not** load the pilot's actual `devbox/commands/db.yml` from devbox-cli tests — that would couple the two repos. The pilot YAML is only exercised manually (Task 12 manual smoke step) and via the regenerated `docs/reference/commands/db.*.md` diff in Task 14
- [ ] `cd devbox-cli && make test && make lint` — must pass before next task

### Task 13: Pilot — `dump-deploy` command and script
- [ ] in `devbox/commands/db.yml`: add `dump-deploy` command (type=script) with params (`database`, `target_database`, `dump_dir`, `check_exists` bool default false), `env` (DB_NAME, TARGET_DB_NAME via `{{ if }}`, CHECK_EXISTS, DB_USER, DB_PASSWORD), `files.dump` (read, candidates [glob+match name_desc, fallback path], required true, env DUMP_FILE), `script.path: devbox/scripts/db/dump-deploy.sh`
- [ ] new `devbox/scripts/db/dump-deploy.sh` — `set -eu`; optional existence check via `MYSQL_PWD=... $DEVBOX_BIN docker exec -T db -- mariadb -u"$DB_USER" -Nse 'SHOW DATABASES LIKE ...'`; drop and recreate using `--set` and `--yes` flags introduced in Task 9: `"$DEVBOX_BIN" commands run db.drop --set database="$TARGET_DB_NAME" --yes`; same shape for `db.create`; restore via `gunzip -c "$DUMP_FILE" | MYSQL_PWD="$DB_PASSWORD" "$DEVBOX_BIN" docker exec -T db -- mariadb -u"$DB_USER" -D "$TARGET_DB_NAME"`
- [ ] manual smoke: `./bin/devbox commands run db.dump-deploy` after a `dump-create`, verify DB restored; verify the legacy `db.sql.gz` (no date) fallback when no dated dumps exist
- [ ] add a second devbox-cli fixture `internal/commands/testdata/files_dump_deploy.yml` and extend the loader test from Task 12 to: (a) parse and validate the fixture (read mode + candidates + glob + match + sort); (b) using a `t.TempDir()` that contains both `db_2026-04-28.sql.gz` and `db_2026-04-29.sql.gz`, run `ComputeFilePaths` and assert `${files.dump.path}` resolves to the absolute path of `db_2026-04-29.sql.gz` (sort=name_desc); (c) `BuildEnv` returns `DUMP_FILE=<that absolute path>` plus templated `DB_USER`/`DB_PASSWORD` from a fixture `Raw` config
- [ ] `cd devbox-cli && make test && make lint` — must pass before next task

### Task 14: Documentation updates
- [ ] update `CLAUDE.md` — add a short "Files directive" subsection under "Config model" describing `files:` shape, access modes, candidates fallback, env injection, safe-cleanup semantics (existed_before), and the `${files.<id>.path}` template form
- [ ] update `CLAUDE.md` — add `date`, `datetime`, `base`, `dir` to the template-funcs note; add `DEVBOX_BIN`, `DEVBOX_FILES_JSON` to script contract list; document `--yes` on `commands run`
- [ ] regenerate reference docs: `./bin/devbox docs generate` (verify diff is sensible, not noise)
- [ ] if `AGENTS.md` exists in either repo, mirror the same notes there
- [ ] no tests for docs

### Task 15: Verify acceptance criteria
- [ ] verify all spec items: `files:` block parses; access modes work; candidates with glob+match+sort work; mkdir/overwrite/on_error work; env injection w/ conflict guard works; `${files.<id>.path}` works in templates **including `confirmation_text`**; `date`/`datetime`/`base`/`dir` funcs work; `DEVBOX_BIN` set in scripts; `--yes` skips confirmation and propagates to nested calls
- [ ] verify safe cleanup: trigger a forced failure during `dump-create` against an **existing** dated dump → confirm the existing file is **preserved** (existed_before=true)
- [ ] verify safe cleanup: trigger a forced failure during `dump-create` against a fresh path → confirm the partial file **is** removed (existed_before=false)
- [ ] verify backward compatibility: at least one existing command without `files:` still loads, validates, and runs unchanged (run `db.up` or similar)
- [ ] full devbox-cli test suite: `cd devbox-cli && make test && make lint` — all green
- [ ] verify `./bin/devbox docs generate` output is current and committed
- [ ] verify both repos compile and their commits are ready to push

### Task 16: Final commits in both repos
- [ ] devbox-cli: stage final docs (regenerated reference, doc comment edits) and commit if anything still pending; ensure branch `commands` is clean
- [ ] pilot repo: stage `devbox/commands/db.yml` additions, new scripts, `CLAUDE.md`, regenerated `docs/reference/commands/db.*.md`; commit with message `feat: add db.dump-create and db.dump-deploy via files: directive`
- [ ] both repos `git status` clean at end

## Technical Details

### YAML shape

```yaml
files:
  <id>:
    access: read | write | read_write   # required
    path: string                        # template; mutually exclusive with candidates
    candidates:                         # ordered list, first hit wins (read modes)
      - path: string
      - glob: string
        match: string                   # regex on basename (templated)
        sort: name_asc | name_desc | modtime_asc | modtime_desc
    required: bool                      # default false
    mkdir: bool                         # write/read_write only
    overwrite: bool                     # write/read_write only
    on_error: keep | remove             # write/read_write only; default keep
    env: string                         # env var name to inject
```

### Resolution flow (in `RunCommand`)

File handling is split into a non-mutating compute phase and a mutating effects phase, gated by user confirmation:

0. **Defensive init** — if `ctx.Render == nil`, allocate an empty `tpl.RenderContext`; if `Render.Raw == nil` and `ctx.Config != nil`, copy `ctx.Config.Raw` in; ensure `Render.Params`/`Render.Context` are at least empty maps. This keeps existing programmatic test callers (which pass `RunContext{Render: nil}`) compatible.
1. `paths, err := ComputeFilePaths(ctx)` — *new, pure* — renders `path`/`candidates` templates, normalizes relative paths against `ctx.ProjectRoot`, runs read-mode discovery (path-stat + glob+match+sort fallback). No `mkdir`, no overwrite check, no writes.
2. `ctx.Render.Files = paths` — exposes `${files.<id>.path}` to **all** subsequent template renders, including `confirmation_text`.
3. `ConfirmCommand(ctx)` (existing) — may now reference resolved paths in its prompt.
4. `cleanups, err := PrepareFileEffects(ctx, paths)` — *new, mutating* — for `write` entries with `mkdir: true`: `os.MkdirAll(filepath.Dir(path), 0o755)`; for `write` entries: stat the path, fail if `overwrite: false` and exists, otherwise record `existedBefore`. Returns cleanup callbacks only for `write` entries where `on_error: remove` **and** `existedBefore == false`.
5. Build env via `BuildEnv` (incl. file env vars) and dispatch to runner via `NewRunner` + `Run`.
6. On runner error: invoke `cleanups` in LIFO order, return error (cleanup errors logged to stderr but do not mask the original).
7. On success: emit success message (existing); cleanups discarded.

### Path normalization contract

Every rendered `path` and `glob` (in both `path` and `candidates[*]`) follows this rule:

```
root := ctx.ProjectRoot
if root == "":
    root, _ = os.Getwd()    // mirrors runner_script.go:79-85 fallback for programmatic callers
if filepath.IsAbs(rendered):
    final = filepath.Clean(rendered)
else:
    final = filepath.Clean(filepath.Join(root, rendered))
```

The normalized absolute path is what gets stored in `tpl.ResolvedFile.Path`, what `${files.<id>.path}` renders to, and what is injected into env vars via `spec.Env`. Scripts and runners always receive absolute paths regardless of the host process's working directory. The `os.Getwd()` fallback keeps existing programmatic test callers — which today construct a `RunContext{ProjectRoot: ""}` — working without forcing them to wire a project root just to render a relative path. This mirrors `runner_script.go`'s existing fallback at lines 79-85.

### Access mode → spec shape matrix

| access      | path required | candidates allowed | mkdir | overwrite | required (input) | presence required (effective) |
|-------------|---------------|--------------------|-------|-----------|------------------|-------------------------------|
| read        | one of ↓      | one of ↓           | no    | no        | optional         | only if `required: true`      |
| write       | yes           | **rejected**       | yes   | yes       | optional (no-op) | n/a (write creates)           |
| read_write  | one of ↓      | one of ↓           | no    | no        | ignored          | always (file must pre-exist)  |

For `read` and `read_write`, exactly one of `path` or `candidates` is required. For `write`, only `path` is allowed (no fallback semantics for a file that doesn't exist yet). For `read_write`, the YAML `required:` field is **ignored at runtime** — presence is always enforced because read semantics require the file to exist. The resolver in Task 4 implements this invariant; the `FileSpec.Required` field stays a plain `bool` (no pointer / custom unmarshal) and is documented as a no-op for read_write.

### Safe `on_error: remove` semantics

The cleanup never deletes a file that pre-existed this invocation:

| access      | path existed before run | on_error  | runner failed | action               |
|-------------|-------------------------|-----------|---------------|----------------------|
| write       | yes                     | remove    | yes           | **preserve** (skip)  |
| write       | no                      | remove    | yes           | remove               |
| write       | yes                     | remove    | no            | n/a (success)        |
| write       | any                     | keep      | yes           | preserve             |
| read_write  | yes (always)            | remove    | yes           | **preserve** (skip)  |
| read        | n/a                     | n/a       | n/a           | no cleanup possible  |

This protects yesterday's dump from a botched re-run today. For `read_write`, `on_error: remove` is effectively a no-op (file pre-existed by definition); validation accepts the combination but documents it as defensive-only.

### Template func contract

| Func        | Signature      | Output                                       |
|-------------|----------------|----------------------------------------------|
| `date`      | `() string`    | local `YYYY-MM-DD`                           |
| `datetime`  | `() string`    | local `YYYY-MM-DD_HH-MM-SS`                  |
| `base`      | `(p) string`   | `filepath.Base(p)` (OS-aware separators)     |
| `dir`       | `(p) string`   | `filepath.Dir(p)` (OS-aware separators)      |

All time funcs use machine-local time (not UTC), matching user expectation for local devbox commands. `base` and `dir` use the `path/filepath` package (filesystem paths), not `path` (slash-only URL paths), because the `files:` directive deals with real local files.

### `BuildEnv` signature change

Today: `BuildEnv(cmd, params, ctx) map[string]string` (pure, can't fail).
After Task 6: `BuildEnv(cmd, params, ctx, files) (map[string]string, error)`.

The new signature is mechanically propagated to all current callers (`runner_host.go` x2, `runner_service.go` x2, `runner_script.go` x1, plus the wrapper `buildRenderedEnv`). The `files` arg may be nil — backward-compatible behaviour is preserved when no `files:` block is declared. The error result is reserved for env-name conflicts; under normal use it is always `nil` because Task 1 validation rejects conflicts at load time.

### Candidate fallback contract

For read / read_write modes with `candidates: [...]`:

- Iterate in declared order.
- A candidate is "missing" when `path` resolves to a non-existent file (`os.ErrNotExist`) or `glob` produces zero matches after `match` filtering.
- A missing candidate is **not** an error — proceed to the next candidate.
- Other errors (permission denied, malformed regex, glob syntax error) abort immediately with the candidate index in the error message.
- Only after iterating *all* candidates without a hit does presence-required raise the final error.
- Outcome when all candidates miss depends on access mode:
  - `read` + `required: true` → error
  - `read` + `required: false` (or omitted) → file id omitted from the result map; `${files.<id>.path}` renders to empty string
  - `read_write` → error (presence is always required for read_write; see access-mode matrix above)

### Confirmation routing — completing the four-way dispatch

CLAUDE.md describes the dispatch order:
1. `SkipConfirm` flag set → no-op
2. `ConfirmFunc` injected → callback
3. TTY → `ui.RunConfirm`
4. Otherwise → plain stdin Y/n

The current code only implements tiers 3 and 4. Task 9 adds tier 1 (`SkipConfirm` field on `RunContext`, honored by `ConfirmCommand`) and threads it through `WorkflowRunner` to nested step contexts. Tier 2 (`ConfirmFunc`) is **not** in scope for this plan — CLAUDE.md mentions it for tests, but no tests actually use it today. We stay aligned with current tests by exposing only the field they need.

The `--yes` CLI flag wires both `SkipConfirm = true` and `NonInteractive = true`. The latter ensures that `runner_workflow.go`'s `confirm:` step (which has its own non-interactive auto-skip) and `runner_script.go`'s `DEVBOX_NONINTERACTIVE` contract env both honor the bypass, even when the host TTY is still attached.

For deeply-nested invocations (parent `--yes` → spawns script → script calls `devbox commands run X`), the bypass propagates as follows:
1. parent `commands run --yes` sets `RunContext.NonInteractive = true`
2. `runner_script.buildContractEnv` propagates `DEVBOX_NONINTERACTIVE=1` into the script's process env
3. the script process spawns `devbox commands run X`; the child inherits `DEVBOX_NONINTERACTIVE=1` via `os.Environ`
4. the child's `internal/command/command_cmd.go` entry maps `DEVBOX_NONINTERACTIVE=1` → `RunContext.SkipConfirm = true` and `RunContext.NonInteractive = true` (Task 9, env→context mapping)
5. the child's `ConfirmCommand` returns nil for tier 1, no prompt shown

Without step 4, a nested command-level `Confirmation: true` could still prompt despite `--yes` at the top.

### Script contract additions

```text
DEVBOX_BIN          absolute path to current devbox executable (os.Executable())
DEVBOX_FILES_JSON   JSON object { "<id>": { "path": "..." } }; empty {} when no files
```

### Env-conflict guard

A spec like `files: { dump: { env: DUMP_FILE } }` reserves `DUMP_FILE`. Validation rejects:
- another `files` entry declaring `env: DUMP_FILE`
- `params.<x>.env: DUMP_FILE`
- `context.<x>.env: DUMP_FILE`
- `env: { DUMP_FILE: ... }`

Same name twice → `command "X": env conflict: DUMP_FILE declared by files.dump and env block`.

### File ID grammar and `ResolvedFile` placement

- File IDs must match `^[a-zA-Z_][a-zA-Z0-9_]*$` (no hyphens, no dots). Reason: the existing `${...}` regex (`varPattern` in `tpl/render_command.go`) only matches identifier characters; `${files.foo-bar.path}` would not be rewritten and would surface as a literal string. Validation enforces this at load time so the failure mode is a clear error, not silent template misbehaviour.
- `ResolvedFile` lives in the `tpl` package as a tiny DTO `type ResolvedFile struct { Path string }`. Chosen over `map[string]map[string]any` for type safety; chosen over a `commands.ResolvedFile` to avoid an `tpl → commands` import cycle (commands already imports tpl). The DTO is intentionally minimal — adding fields later (e.g. `Existed bool`) is a non-breaking change.

### `--` separator and nested confirmation

- `docker compose exec/run` accepts `--` natively (verified by `internal/docker/compose_test.go:217`). The cobra commands in `internal/command/docker.go` must forward unparsed args verbatim — Task 10 audits this and adds a regression test.
- Nested `devbox commands run` calls (e.g. `db.dump-deploy` invoking `db.drop`) bypass confirmation via the new `--yes` flag (Task 9). The flag also sets `DEVBOX_NONINTERACTIVE=1` in the subprocess env so any deeper nesting also stays non-interactive.

## Post-Completion

*Items requiring manual intervention or external systems — informational only.*

**Manual verification**:
- Run `devbox commands run db.dump-create` against a live MariaDB and confirm `services/main/runtime/dumps/<db>_<YYYY-MM-DD>.sql.gz` is created
- Run `devbox commands run db.dump-deploy` and confirm the database is restored from the most recent dated dump
- Simulate failure during `dump-create` (e.g. wrong DB password) when **no** target file pre-exists at the rendered path: confirm `on_error: remove` deletes the partial file (existed_before=false branch)
- Simulate the same failure when a target file **already exists** at the rendered path (e.g. re-run `dump-create` twice on the same date): confirm the **pre-existing dump is preserved** untouched (existed_before=true branch — the safe-cleanup invariant)
- Confirm legacy non-dated `db.sql.gz` fallback still works for `dump-deploy` when no dated dumps exist

**External system updates**: none — feature is local to the devbox tooling.
