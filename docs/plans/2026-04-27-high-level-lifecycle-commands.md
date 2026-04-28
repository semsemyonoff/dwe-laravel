# High-level lifecycle commands: run / stop / restart

## Overview

Promote `devbox run`, `devbox stop`, `devbox restart` into high-level project lifecycle entrypoints driven by a declarative pipeline (`devbox/lifecycle.yml`), while keeping `devbox up` / `devbox down` as thin Docker Compose passthroughs (and `devbox docker ...` as the low-level control plane).

After this change:

- `devbox up`  — only brings up the compose stack (unchanged).
- `devbox down` — only stops and removes the compose stack (unchanged).
- `devbox run` — full project start: optional git update probe → before-run hooks → `devbox docker up` → `devbox docker wait` → after-run hooks → `devbox info` → final ready message.
- `devbox stop` — full project shutdown: before-stop hooks → `devbox docker down` → after-stop hooks → final goodbye message. (No longer a `docker compose stop` passthrough — that operation remains available via `devbox docker stop`.)
- `devbox restart` — `devbox stop` then `devbox run --no-update`.

The lifecycle pipelines are executed by the existing pipeline executor (`runPipeline`, `resolvePhaseSteps`) with the same step types (`run`, `devbox`, `command`, `builtin`) and the same `PlainReporter`. A new step-level field `continue_on_error` is added so hook phases can fail without aborting the main scenario (the legacy `-@make private_jobs_*` behavior).

## Context (from discovery)

- **Existing pipeline plumbing** is fully reusable:
  - `devbox-cli/internal/command/pipeline.go` — `runPipeline`, `resolvePhaseSteps`, `execStep`, `execBuiltinStep`, `execCommandStep`, `buildDevboxCmd`, ANSI stripper, log tee.
  - `devbox-cli/internal/pipeline/plain.go` — `PlainReporter` with phase/step icons, untracked-phase suppression, elapsed time.
  - `devbox-cli/internal/config/devbox.go` — `LoadDeployConfig` / `LoadResetConfig` share `loadPipelineConfig`; both produce `DeployConfig{Phases []DeployPhase}`. Reset is the cleanest template (separate YAML, separate loader, plain reporter, log file in `logs/reset.log`).
- **Existing root commands to rework** (`devbox-cli/internal/command/`):
  - `up.go`, `down.go` — keep as thin passthroughs to `newDockerPipeline(...).compose.Exec("up"|"down", ...)`.
  - `stop.go`, `restart.go` — replace bodies; old compose semantics remain accessible via `devbox docker stop` / `devbox docker restart`.
  - `run.go` — does **not** exist; create new file. (No conflict with existing `commands run` subcommand inside `command_cmd.go`.)
- **Tests touching these commands**:
  - `lifecycle_test.go` — verifies `up/down/stop/restart/logs/ps/wait` exist at root and have expected `Use` strings; will need updating for new `run` command and new `Use` strings.
  - `docker_test.go`, `compose_test.go`, `coverage_test.go` — should be unaffected; verify no regressions.
- **Step schema** in `devbox-cli/internal/config/devbox.go`: `DeployStep` already has Name/Run/Devbox/Command/Builtin/With/Description/When/Check. Need to add `ContinueOnError bool` (yaml: `continue_on_error`).
- **devbox-cli is a separate git repo** (remote `git@github.com:semsemyonoff/devbox-next-cli.git`, currently on `main`). All Go work happens there on its own feature branch with its own commits. Pilot-repo work (Makefile facade, `devbox/lifecycle.yml`, CLAUDE.md, `docs/plans/`, generated `docs/reference/`) commits in this repo (`next-laravel`).
- **Makefile facade** currently delegates `up/down/stop/restart` 1:1 to the CLI. After this change, the facade does not need code changes (it still calls the same commands), but the user-facing semantics shift; the facade docstrings/comments should be reviewed.
- **Update probe** is greenfield — no existing git helper in devbox-cli. Will live in a new `devbox-cli/internal/git/` package.

## Development Approach

- **Testing approach**: Regular (implement, then write tests for new/changed functionality before moving on).
- Complete each task fully before moving to the next.
- Make small, focused changes.
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task.
  - tests are not optional — they are a required part of the checklist.
  - write unit tests for new functions/methods.
  - write unit tests for modified functions/methods.
  - cover both success and error scenarios.
- **CRITICAL: all tests must pass before starting next task** — no exceptions.
- **CRITICAL: update this plan file when scope changes during implementation.**
- Run `cd devbox-cli && make test && make lint` after each task that touches Go code.
- Run `cd devbox-cli && make build` to refresh `bin/devbox` whenever behavior changes.
- Maintain backward compatibility for unrelated subcommands; `up`/`down`/`docker ...`/`deploy`/`reset` semantics must not regress.

## Testing Strategy

- **Unit tests**: required for every task that touches Go code.
  - Config loader: golden YAML files + parse error cases.
  - Step `ContinueOnError`: table-driven test of `runPipeline` with a failing step that has the flag on/off.
  - Git update probe: stub git via injected runner interface (no real git invocation in unit tests).
  - Lifecycle commands: cobra wiring tests (flag definitions, Args, exact-arg counts, `Use` strings).
- **Integration**: a minimal `devbox/lifecycle.yml` is committed to the pilot repo; manual smoke run (`./bin/devbox run`, `./bin/devbox stop`, `./bin/devbox restart`) is part of the final acceptance task.
- **No e2e UI tests** in this project.

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix.
- Document issues/blockers with ⚠️ prefix.
- Update plan if implementation deviates from original scope.
- Keep plan in sync with actual work done.

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): code, config, generated docs, tests.
- **Post-Completion** (no checkboxes): manual smoke verification, behavior checks across multiple terminals/CI shapes, follow-up legacy migration in other consuming projects.
- **Checkbox placement**: only in Task sections.

## Repository workflow

- All Go changes happen inside `devbox-cli/` (separate git repo, remote `devbox-next-cli`).
  - Create feature branch `feat/lifecycle-commands` off `main` in `devbox-cli/`.
  - Commit per task (or per logical unit) with conventional-commit style messages.
  - Final step: push the branch and open a PR in `devbox-next-cli`.
- Pilot-repo changes (this repo, `next-laravel`) — `Makefile`, `devbox/lifecycle.yml`, `devbox/lifecycle.example.yml`, `AGENTS.md`, `docs/plans/`, regenerated `docs/reference/cli/` — commit directly on `main` in step with each task. This matches the established workflow in this pilot (recent plan completions landed directly on `main`, e.g. d55ef44, 96dc4cc). **No PR for the pilot repo.**

## Implementation Steps

### Task 1: Branch setup in devbox-cli repo
- [x] in `devbox-cli/`, confirm working tree is clean and `main` is up to date with `origin/main`
- [x] in `devbox-cli/`, create branch `feat/lifecycle-commands`
- [x] no tests in this task (branch-only)
- [x] verify `cd devbox-cli && make test` still passes on the new branch (baseline)

### Task 2: Add `continue_on_error` to DeployStep and honor it in runPipeline
- [x] add `ContinueOnError bool \`yaml:"continue_on_error"\`` to `DeployStep` in `devbox-cli/internal/config/devbox.go`
- [x] document the new field in the `DeployStep` doc comment (semantics: when true, a failed step is reported via `FailStep` but the pipeline does not abort — the next step runs as if nothing happened)
- [x] update `runPipeline` in `devbox-cli/internal/command/pipeline.go`:
  - on `stepErr != nil`, if `rs.step.ContinueOnError` is true, call `rep.FailStep(...)` then `continue` instead of `return ErrSilent`
  - the post-step hook and `Check` are skipped when the step failed (no behavior change for non-skipping path)
- [x] add `ContinueOnError` reflection only in **human table output** (`printDeployPlanTable` in `pipeline.go`): emit a small suffix tag like `[continue_on_error]` on the detail line for the step. Do **not** modify `stepCommand` — its return value is also consumed by shell-plan generation, where any non-shell tag would produce invalid output.
- [x] update shell-plan generation (`printDeployPlanShell` and `printResetPlanShell` in `pipeline.go` / `reset.go`) so that steps with `ContinueOnError: true` are emitted as `<command> || true` instead of being aborted by the leading `set -e`. Builtin-dispatch lines (`./bin/devbox deploy step ...` / `./bin/devbox reset step ...`) get the same treatment. Lifecycle commands do **not** expose a shell-plan flag (Task 6 / 7 only ship `run`/`stop`, no `plan` subcommand), so this only affects deploy/reset shell plans, which is the desired forward-compat behavior.
- [x] write unit tests in `devbox-cli/internal/command/pipeline_run_test.go` (or new file) for `runPipeline` covering: (a) failing step without flag aborts as today, (b) failing step with flag continues, (c) check/post-step-hook are not run after a failed-but-continued step, (d) shell plan output contains `|| true` exactly when `ContinueOnError` is set
- [x] run `cd devbox-cli && make test && make lint` — must pass before next task

### Task 3: Add LifecycleConfig schema and loader
- [x] in `devbox-cli/internal/config/devbox.go`, add types:
  - `LifecycleConfig{ Run *LifecycleRunConfig; Stop *LifecycleStopConfig }`
  - `LifecycleRunConfig{ Update *LifecycleUpdate; ShowInfo bool; FinalMessage string; Phases []DeployPhase }` — note: `Update` is a **pointer** so we can distinguish "block omitted" (`nil`) from "block present with defaults"
  - `LifecycleStopConfig{ FinalMessage string; Phases []DeployPhase }`
  - `LifecycleUpdate{ Enabled *bool; Mode string; Strategy string }` — `Enabled` is `*bool` so absent (`nil`) is distinguishable from explicit `false`. `Mode` ∈ {`prompt`, `auto`, `check`, `off`}; `Strategy` defaults to `ff-only`
- [x] schema-presence rule (encoded in `LoadLifecycleConfig`):
  - if the `update:` block is **omitted entirely** → `Run.Update` stays `nil` → effective mode is `off` (i.e., user must explicitly opt in to the probe)
  - if the `update:` block is **present** but `enabled:` is omitted → `Update.Enabled` is set to `&true` at load time (writing `update:` is itself the opt-in)
  - if `enabled: false` is set explicitly → effective mode `off`, even if `mode:` is set
- [x] add a method `func (cfg *LifecycleRunConfig) EffectiveMode() string` that resolves the precedence rule **before any CLI flag is applied**:
  - if `cfg.Update == nil` → returns `"off"`
  - if `cfg.Update.Enabled == nil` → defensive: treat as `"off"` (loader is responsible for setting it; this branch only fires if a caller bypasses the loader)
  - if `*cfg.Update.Enabled == false` → returns `"off"`
  - if `*cfg.Update.Enabled == true` and `Mode` is empty → returns `"prompt"` (default within an opted-in block)
  - if `*cfg.Update.Enabled == true` and `Mode` is set → returns `Mode` (validated to one of `prompt`/`auto`/`check`/`off`)
  - the CLI flag (`--update`) layered on top in Task 6 still wins, which lets users force-enable an update probe even when the project disables it by default
- [x] add `LoadLifecycleConfig(path string) (*LifecycleConfig, error)`:
  - reuse the same `loadPipelineConfig` step-validation helper for each section's phases (factor it so it can validate a `[]DeployPhase` slice without requiring the wrapping `DeployConfig` shape — small refactor)
  - return `os.ErrNotExist` when missing (callers may treat as optional)
  - reject `deploy_services: true` phases in lifecycle pipelines (lifecycle is orchestrator-only, no per-service expansion)
  - when `Update` is non-nil: default `Update.Strategy = "ff-only"` if empty; if `Enabled` is nil, set it to a pointer to `true` (writing the block opts in)
  - validate that `Update.Mode`, when set, is one of the four allowed values; reject otherwise
  - default `FinalMessage` strings at load time: if `Run` is non-nil and `Run.FinalMessage == ""`, set it to `"Project is ready for work!"`; if `Stop` is non-nil and `Stop.FinalMessage == ""`, set it to `"Project is stopped. Have a nice day!"`. Centralizing the defaults in the loader keeps the command code free of magic strings and makes the defaults visible in unit tests of `LoadLifecycleConfig`.
- [x] write unit tests `devbox-cli/internal/config/devbox_test.go`:
  - happy path (full lifecycle.yml fixture)
  - missing file → `os.ErrNotExist`
  - invalid step (e.g. two of run+devbox set) → error
  - rejected `deploy_services: true` phase
  - default mode/strategy when `update:` block present but `mode`/`strategy` omitted
  - invalid `update.mode` value → error
  - default `FinalMessage` for both `Run` and `Stop` when omitted in YAML; explicit values are preserved when set
  - `EffectiveMode` table-driven test: (a) `update:` block omitted → `off`, (b) block present, `enabled` omitted → `prompt`, (c) `enabled: true` + `mode: auto` → `auto`, (d) `enabled: false` + `mode: auto` → `off`, (e) `enabled: true` + `mode` omitted → `prompt`
- [x] run `cd devbox-cli && make test && make lint`

### Task 4: Git update probe package
- [x] create `devbox-cli/internal/git/git.go` with:
  - `type Status struct { IsRepo bool; HasUpstream bool; Branch string; Upstream string; Dirty bool; Behind int; Ahead int; FetchOK bool; FetchErr string }`
  - `func Probe(workDir string, fetch bool) (Status, error)` — order of operations. The `fetch` argument is a pure boolean (caller computes it; `Probe` knows nothing about update modes):
    1. `git rev-parse --is-inside-work-tree` (sets `IsRepo`; if false, returns early with all-zero status)
    2. `git status --porcelain` (sets `Dirty`)
    3. `git rev-parse --abbrev-ref HEAD` (sets `Branch`)
    4. `git rev-parse --abbrev-ref --symbolic-full-name @{u}` (sets `HasUpstream` and `Upstream`; absence of upstream is non-fatal)
    5. **if `fetch == true` and `HasUpstream == true`**: parse `Upstream` (e.g. `origin/main`) into `<remote>/<branch>` and run `git fetch --quiet <remote>` (no refspec — fetch the whole remote so the standard refspec `+refs/heads/*:refs/remotes/<remote>/*` updates the remote-tracking ref that `rev-list <upstream>...HEAD` reads in step 6). Use a 15s context timeout. On success, set `FetchOK = true`. On failure, capture the stderr into `FetchErr` and set `FetchOK = false`; do **not** propagate as an error — the probe still returns a populated `Status` so the caller can warn and continue offline. When `fetch == false`, `FetchOK` stays false and `FetchErr` stays empty (the absence of attempt is distinguishable from a failed attempt by `FetchErr == ""`).
    6. `git rev-list --left-right --count <upstream>...HEAD` (sets `Behind`, `Ahead`); only meaningful after a successful fetch — if `FetchOK == false`, the counts come from stale remote-tracking refs and the policy must treat them as unreliable (see `Decide`).
  - `func PullFFOnly(workDir string) (moved bool, err error)` — captures `git rev-parse HEAD` before, runs `git pull --ff-only` with stdout/stderr passthrough, captures HEAD again, returns `moved = (before != after)` so callers can decide whether to reload config
  - inject a small `runner` interface (default backed by `os/exec`) so unit tests can stub git invocations without touching a real repo. The runner exposes `Run(ctx, dir, args...) (stdout, stderr string, err error)` so timeouts and stub patterns are explicit.
- [x] create `devbox-cli/internal/git/policy.go` with `type UpdateMode string`, `type Action int` (`ActionSkip`, `ActionWarn`, `ActionPullAuto`, `ActionPullPrompt`), and `Decide(status Status, mode UpdateMode, isInteractive bool) (action Action, msg string)`. Encodes the safety matrix:
  - mode=off → skip
  - not a repo → skip
  - dirty worktree → warn (no pull) — message names dirty paths if reasonable
  - no upstream → warn (no pull)
  - **fetch failed** (`FetchOK == false`) → warn ("could not contact remote: <FetchErr>") and skip (we don't trust stale counts to drive a pull, and we don't want to block lifecycle on offline)
  - diverged (ahead > 0 && behind > 0) → warn (no pull)
  - clean and behind, mode=auto → pull
  - clean and behind, mode=prompt + TTY → prompt-pull
  - clean and behind, mode=prompt + non-TTY → warn (no pull)
  - clean and behind, mode=check → warn (no pull)
  - up to date → skip
- [x] write unit tests for both files: stub the runner for `Probe` golden cases (incl. fetch-success, fetch-timeout, no-upstream); table-driven test for `Decide` covering every matrix row including the new fetch-failed case
- [x] run `cd devbox-cli && make test && make lint`

### Task 5: Lifecycle pipeline runner helper
- [x] in `devbox-cli/internal/command/`, add `lifecycle.go` (new file) with `runLifecyclePhases(cfg, reg, workDir, phases, name, logFileName, skipConfirm) error`:
  - resolves phases via `resolvePhaseSteps` (reusing the existing helper, with empty service)
  - opens `logs/<logFileName>.log` and tees output exactly like reset.go does
  - constructs `PlainReporter` and calls `runPipeline`
  - returns `ErrSilent` propagation matching reset semantics
- [x] write unit tests for `runLifecyclePhases` with a stub temp workDir and a minimal phase list (e.g., one `run: "true"` step plus one `run: "false"` step with `continue_on_error: true`):
  - verify the helper returns nil on the happy path and `ErrSilent` when an aborting step fails
  - verify the log file at `logs/<logFileName>.log` exists, is non-empty, and contains ANSI-stripped output for the executed steps
  - **scope note:** reporter event semantics (icons, untracked-phase suppression, elapsed time) are already covered by `runPipeline` / `PlainReporter` tests in `pipeline_run_test.go` and `internal/pipeline/plain_test.go`. The lifecycle helper does not re-test those — it only needs to verify the wiring (log file written, error propagation correct). No reporter injection is added.
- [x] run `cd devbox-cli && make test && make lint`

### Task 6: `devbox run` command
- [ ] create `devbox-cli/internal/command/run.go` with `newRunCmd(flags *rootFlags) *cobra.Command`:
  - flags: `--no-update` (force-disable update probe regardless of config), `--update string` (override `mode`: prompt/auto/check/off), `-y/--yes` (skip confirmation prompts inside hook steps)
  - `Args: cobra.NoArgs`
  - implementation order:
    1. load `DevboxConfig`, then `LoadLifecycleConfig` (if file missing → friendly error: "no lifecycle.yml — see devbox/lifecycle.example.yml")
    1a. require `lifecycleCfg.Run != nil` — if the file is present but `run:` block is missing, fail with: "lifecycle.yml has no `run:` section — see devbox/lifecycle.example.yml". This guard runs before any pointer dereference on `lifecycleCfg.Run`.
    2. resolve effective update mode with strict precedence: **`--no-update` flag** (forces `off`) > **`--update <mode>` flag** > **`lifecycleCfg.Run.EffectiveMode()`** (which already encodes `update:` block omitted → `off`, `enabled: false` → `off`, `enabled: true + mode unset` → `prompt`, validated otherwise)
    3. run update probe via `git.Probe(workDir, fetch)` where `fetch := effectiveMode != "off"` (the caller computes the fetch flag from the resolved mode — `Probe` does not know about modes). Then `git.Decide(status, effectiveMode, ui.IsInteractiveFn(os.Stdin))`. On `ActionPullPrompt` use `ui.RunConfirm`; on `ActionPullAuto` call `git.PullFFOnly` and capture the `moved` return value; on warn paths emit a Warning via `render.Writer`; on skip be silent (or info-level when explicitly off).
    4. **if `PullFFOnly` returned `moved == true`**, reload all three of: `DevboxConfig`, `LifecycleConfig`, and the command registry from disk. From this point on, the command must use the reloaded `lifecycleCfg.Run.Phases`, `lifecycleCfg.Run.ShowInfo`, and `lifecycleCfg.Run.FinalMessage` — never the pre-pull copy. Note: a config reload after pull does **not** re-run the update probe (single probe per `devbox run` invocation).
    5. call `runLifecyclePhases(...)` for `lifecycleCfg.Run.Phases` (post-reload value)
    6. on success: if `lifecycleCfg.Run.ShowInfo` is true, run `devbox info` (preferably by calling the existing info renderer in-process with the just-reloaded config — no subprocess); then print `lifecycleCfg.Run.FinalMessage` via `render.Writer.Success` (the default `"Project is ready for work!"` is already applied by the loader; no fallback needed in command code)
- [ ] register the new command in `devbox-cli/internal/command/root.go`
- [ ] write unit tests `run_test.go`:
  - cobra wiring (Use, flags exist, NoArgs)
  - `--no-update` forces probe to off
  - `--update` overrides yaml mode (incl. `enabled: false` and incl. omitted `update:` block)
  - `update:` block omitted in yaml + no `--update` flag → effective mode `off` (no fetch attempted)
  - `update:` block present, `mode:` omitted, no `--update` flag → effective mode `prompt`
  - `enabled: false` + no `--update` flag → effective mode `off` (no fetch attempted)
  - missing lifecycle.yml produces a clear error
  - lifecycle.yml present but `run:` section omitted → clear error mentioning the missing section
  - after a simulated successful pull (HEAD-moved stub), the command uses the reloaded `LifecycleConfig` for `Phases`/`ShowInfo`/`FinalMessage` (drive this via a fixture that swaps lifecycle.yml on disk between probe and phase-run)
- [ ] run `cd devbox-cli && make test && make lint`

### Task 7: Replace `devbox stop` body with lifecycle pipeline
- [ ] rewrite `devbox-cli/internal/command/stop.go`:
  - new `Use: "stop"`, `Args: cobra.NoArgs` (drop `[services...]`; per-service compose stop is now `devbox docker stop <svc>`)
  - update `Short`/`Long` to describe the lifecycle-stop semantics and point to `devbox docker stop` for the raw compose passthrough
  - flag: `-y/--yes` (skip confirmations)
  - load `DevboxConfig` + `LoadLifecycleConfig`; missing file → friendly error
  - require `lifecycleCfg.Stop != nil` — if the file is present but `stop:` block is missing, fail with: "lifecycle.yml has no `stop:` section — see devbox/lifecycle.example.yml". This guard runs before any pointer dereference on `lifecycleCfg.Stop`.
  - call `runLifecyclePhases(...)` for `lifecycleCfg.Stop.Phases`
  - on success print `lifecycleCfg.Stop.FinalMessage` via `render.Writer.Success` (the default `"Project is stopped. Have a nice day!"` is already applied by the loader; no fallback needed in command code)
- [ ] write unit tests in `stop_test.go` (new) for cobra wiring and basic config-loading behavior, including: missing lifecycle.yml → clear error; lifecycle.yml present but `stop:` section omitted → clear error mentioning the missing section
- [ ] update `lifecycle_test.go` to reflect the new `Use` string for `stop` (no `[services...]`)
- [ ] run `cd devbox-cli && make test && make lint`

### Task 8: Rewrite `devbox restart` to delegate to stop + run
- [ ] rewrite `devbox-cli/internal/command/restart.go`:
  - new `Use: "restart"`, `Args: cobra.NoArgs`
  - update `Short`/`Long`: "Restart the project (stop, then run --no-update)" and point to `devbox docker restart` for the raw compose passthrough
  - flags: `-y/--yes`; pass through to both child invocations
  - implementation: directly call the same in-process helpers used by `stop` and `run` (do NOT shell out to `./bin/devbox`); for `run`, force `--no-update` so the update probe is skipped on the second leg
- [ ] write unit tests in `restart_test.go` covering cobra wiring + the no-update propagation. Note: section-presence guards live inside the underlying stop/run helpers, so a `restart` call against a partial `lifecycle.yml` (e.g. only `run:` defined) surfaces the stop-side missing-section error during the stop leg — no extra guard is needed in `restart.go`. The test should assert this behavior.
- [ ] update `lifecycle_test.go` to reflect the new `Use` string for `restart`
- [ ] run `cd devbox-cli && make test && make lint`

### Task 9: Wire `up` / `down` documentation and audit Makefile
- [ ] update `Long` strings on `up.go` and `down.go` to make the contrast explicit ("low-level Docker Compose operation; see `devbox run` / `devbox stop` for the full project lifecycle")
- [ ] no behavior change to `up`/`down`
- [ ] in this repo (`next-laravel`), review `Makefile` targets `up/down/stop/restart` — they continue to call the same CLI commands, but their *user-visible behavior* now changes (the make targets `make stop`/`make restart` will trigger lifecycle pipelines, not bare compose stop/restart). Add a short comment in `Makefile` clarifying this delegation, but no recipe rewrite is needed.
- [ ] regression tests: ensure existing `up_test.go`/`down_test.go` (if present) still pass; otherwise add minimal cobra wiring tests to assert `Args` and `Use`
- [ ] run `cd devbox-cli && make test && make lint`

### Task 10: Ship a working `devbox/lifecycle.yml` and example file
- [ ] in this repo (`next-laravel`), create `devbox/lifecycle.yml` with a minimal but functional pipeline:
  - `run.update.enabled: true`, `run.update.mode: prompt`
  - `run.show_info: true`, `run.final_message: "Project is ready for work!"`
  - `run.phases`: just one `start` phase with `devbox: docker up` then `devbox: docker wait`
  - `stop.final_message: "Project is stopped. Have a nice day!"`
  - `stop.phases`: just one `stop` phase with `devbox: docker down`
  - no `pre`/`post` hook phases (no `project.before-run` etc. commands exist yet — keep YAGNI; add as comments showing the shape with `continue_on_error: true`)
- [ ] also create `devbox/lifecycle.example.yml` (tracked) showing the full shape including pre/post hook phases with `continue_on_error: true` and an `update.mode: auto` example, so users can copy-paste
- [ ] write tests is N/A here (config-only), but verify by running `./bin/devbox run`, `./bin/devbox stop`, `./bin/devbox restart` against the live pilot — record observed output in this plan when running Task 12

### Task 11: Regenerate reference docs and update AGENTS.md
- [ ] in `devbox-cli/`, run `cd devbox-cli && make build` to refresh `bin/devbox`
- [ ] in this repo (`next-laravel`), run `./bin/devbox docs generate` to regenerate `docs/reference/cli/` (the new `run`/`stop`/`restart` long descriptions land there automatically)
- [ ] update `AGENTS.md` in this repo (the canonical project doc; `CLAUDE.md` is a symlink → `AGENTS.md`, so editing `AGENTS.md` is sufficient):
  - Architecture section: add `devbox/lifecycle.yml` and the high-level `run/stop/restart` distinction
  - Project layout: add `devbox/lifecycle.yml` and `devbox/lifecycle.example.yml`
  - devbox-cli "Key patterns" section: add a short bullet on the lifecycle pipeline (separate YAML, separate loader, reuses pipeline executor, supports `continue_on_error` for hook phases)
  - Migration phases: add a short Phase 8 entry summarizing this work
- [ ] no Go test changes; just confirm `cd devbox-cli && make test && make lint` still passes

### Task 12: Verify acceptance criteria
- [ ] `cd devbox-cli && make test` — all green
- [ ] `cd devbox-cli && make lint` — clean
- [ ] `cd devbox-cli && make build` — `bin/devbox` rebuilt
- [ ] `./bin/devbox run --no-update` runs to completion with green ✓ icons, `devbox info` is shown, final message is printed
- [ ] `./bin/devbox stop` runs to completion, final message is printed
- [ ] `./bin/devbox restart` performs stop → run --no-update without prompting for git pull
- [ ] `./bin/devbox up` and `./bin/devbox down` still behave like before (compose-only, no hook execution)
- [ ] `./bin/devbox docker stop` and `./bin/devbox docker restart` still work as raw compose passthroughs
- [ ] `logs/run.log` and `logs/stop.log` are written and contain ANSI-stripped output
- [ ] simulate a behind-upstream state on a scratch branch (or stub via test) and verify `prompt`/`auto`/`check`/`off` modes all behave per the safety matrix
- [ ] simulate a step failure inside a hook phase with `continue_on_error: true` and verify the pipeline reports the failure but completes
- [ ] `./bin/devbox docs generate` produces no diff (already regenerated in Task 11)
- [ ] verify acceptance criteria from Overview are implemented (run order: update probe → before-run → docker up → docker wait → after-run → info → message; stop order: before-stop → docker down → after-stop → message; restart = stop + run --no-update)

### Task 13: Commit, push, and open PR (devbox-cli only)
- [ ] in `devbox-cli/`, ensure all Go changes are committed on `feat/lifecycle-commands` (one commit per task is fine; squash on merge)
- [ ] in `devbox-cli/`, push the branch and open a PR via `gh pr create`
- [ ] in this repo (`next-laravel`), commit `Makefile`/`devbox/lifecycle.yml`/`devbox/lifecycle.example.yml`/`AGENTS.md`/`docs/reference/` changes directly to `main` (no PR — pilot repo workflow)
- [ ] in this repo, ensure the plan file is up to date (all checkboxes ticked) so ralphex auto-moves it to `docs/plans/completed/` on completion

## Technical Details

### lifecycle.yml shape

```yaml
run:
  update:
    enabled: true
    mode: prompt        # prompt | auto | check | off
    strategy: ff-only
  show_info: true
  final_message: "Project is ready for work!"
  phases:
    - name: pre
      steps:
        - name: before-run
          command: project.before-run
          continue_on_error: true
    - name: start
      steps:
        - name: up
          devbox: "docker up"
        - name: wait
          devbox: "docker wait"
    - name: post
      steps:
        - name: after-run
          command: project.after-run
          continue_on_error: true

stop:
  final_message: "Project is stopped. Have a nice day!"
  phases:
    - name: pre
      steps:
        - name: before-stop
          command: project.before-stop
          continue_on_error: true
    - name: stop
      steps:
        - name: down
          devbox: "docker down"
    - name: post
      steps:
        - name: after-stop
          command: project.after-stop
          continue_on_error: true
```

### Update mode resolution

Effective mode is resolved in strict precedence (highest wins):

1. CLI: `--no-update` → `off`
2. CLI: `--update <mode>` (one of `prompt`/`auto`/`check`/`off`)
3. `LifecycleRunConfig.EffectiveMode()` from `devbox/lifecycle.yml`:
   - `update:` block omitted entirely → `off` (writing the block is the opt-in)
   - `update:` block present, `enabled` omitted → defaults to `enabled: true` at load time, then mode resolution below
   - `enabled: false` → `off`
   - `enabled: true` + `mode:` unset → `prompt`
   - `enabled: true` + `mode:` set → that value (validated)
4. Hardcoded fallback (only reached if no `lifecycle.yml`, which already errors earlier in `devbox run`): `off`

### Update mode safety matrix

The probe runs `git fetch` (15s timeout) before evaluating branch state, except when mode is `off` (no fetch attempted at all).

| Worktree | Upstream | Fetch     | Branch state | `prompt` (TTY) | `prompt` (CI) | `auto` | `check` | `off` |
|----------|----------|-----------|--------------|----------------|---------------|--------|---------|-------|
| —        | —        | n/a       | not a repo   | skip           | skip          | skip   | skip    | skip  |
| dirty    | any      | any       | any          | warn           | warn          | warn   | warn    | skip  |
| clean    | none     | n/a       | —            | warn           | warn          | warn   | warn    | skip  |
| clean    | yes      | failed    | unreliable   | warn (offline) | warn          | warn   | warn    | skip  |
| clean    | yes      | ok        | up to date   | skip           | skip          | skip   | skip    | skip  |
| clean    | yes      | ok        | behind       | confirm-pull   | warn          | pull   | warn    | skip  |
| clean    | yes      | ok        | diverged     | warn           | warn          | warn   | warn    | skip  |

A successful pull (HEAD actually moved) triggers an in-process reload of **all** of: `DevboxConfig`, `LifecycleConfig`, and the command registry. From that point, the command must use the reloaded `lifecycleCfg.Run.Phases` / `ShowInfo` / `FinalMessage` — never the pre-pull values. The probe is **not** re-run after reload (single probe per `devbox run`).

### `continue_on_error` semantics

- Step-level boolean on `DeployStep` (yaml: `continue_on_error`).
- When a step fails and the flag is true: `runPipeline` invokes `rep.FailStep(...)` (so the user sees the red ✗ in `PlainReporter`), skips the step's post-step hook and `Check`, and proceeds to the next step.
- The pipeline still finishes with success status (`rep.FinishPipeline(true)`) if no other step fails.
- The flag has no effect on deploy/reset pipelines unless they opt in via the same field — backward compatible.

### CLI flag matrix

| Command            | Flags                                                       |
|--------------------|-------------------------------------------------------------|
| `devbox run`       | `--no-update`, `--update prompt|auto|check|off`, `-y/--yes` |
| `devbox stop`      | `-y/--yes`                                                  |
| `devbox restart`   | `-y/--yes` (forces `--no-update` on the run leg)            |
| `devbox up`        | (unchanged passthrough)                                     |
| `devbox down`      | (unchanged passthrough)                                     |

## Post-Completion

*Items requiring manual intervention or external systems — no checkboxes, informational only.*

**Manual smoke verification:**
- Run `./bin/devbox run` on a fresh shell with TTY and confirm the prompt UX for git update.
- Run `./bin/devbox run` piped (e.g. `echo y | ./bin/devbox run`) and verify the non-TTY fallback behaves correctly (no huh form, no pull in `prompt` mode).
- Run with `--update auto` on a behind branch and confirm a successful `git pull --ff-only` triggers a config reload (e.g. by editing `lifecycle.yml` in the upstream branch and observing the reloaded final message).
- Run with `--update off` and confirm no git activity at all.
- Force a hook failure (e.g. add a hook with `run: "false"` and `continue_on_error: true`) and confirm the pipeline finishes with a red ✗ for that step but a green Done.
- Confirm Ctrl+C during a hook step terminates cleanly (no orphan child processes).

**External system updates:**
- Other devbox pilots / consuming projects on the legacy Make-as-DSL flow can adopt this on their own schedule by adding their own `devbox/lifecycle.yml`. No automatic migration required.
- `make/macros.mk` and the legacy `private_jobs_*` patterns in old repos are now superseded by `continue_on_error`; document this in the migration notes when other pilots come online.
