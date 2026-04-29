# Commands System: Workflow Conditions, Compose Args, Unified Workdir

## Overview

Three small but distinct enhancements to the devbox-cli command system that unblock
migrating remaining legacy Make targets to declarative YAML without resorting to
large shell scripts:

1. **Workflow steps** gain `when` (skip-on-falsy) and `continue_on_error` (non-fatal failures).
   Mirrors the semantics already implemented for deploy/lifecycle pipeline steps.
2. **`compose_args`** is a new field on `service_exec` / `service_run` commands that
   forwards arbitrary flags (e.g. `-T`, `-d`, `--name`, `--rm`) to `docker compose
   exec/run` between the docker policy defaults and the runner-generated
   `--user`/`--workdir`/`-e` flags. Templates resolved from the command render
   context.
3. **`workdir` unification.** Drop the `cwd` field from `type: command` and reuse the
   existing `workdir` field for host commands. Add `workdir` support to
   `type: script` (applied as `exec.Cmd.Dir` of the spawned shell, but **not** used
   to resolve `script.path` — that always remains relative to the project root).
   `workdir_from` is **not** extended to host/script commands.

These changes purposely keep the YAML schema minimal: no parallel/matrix workflows,
no pre-validated docker flag whitelist, no host-side `workdir_from`.

## Context (from discovery)

### Files/components involved

The CLI lives in a separate git repository (`devbox-cli/`, gitignored from the
pilot repo, remote: `git@github.com:semsemyonoff/devbox-next-cli.git`). Each task
that touches Go code produces its own commit there; the pilot repo only sees
demo YAML changes (under `devbox/commands/`) and CLAUDE.md updates.

**Go (devbox-cli repo):**

- `internal/commands/types.go` — `CommandDef`, `WorkflowStep`, validation
- `internal/commands/runner_workflow.go` — workflow step execution loop
- `internal/commands/runner_host.go` — host runner (uses `cmd.Cwd` today)
- `internal/commands/runner_script.go` — script runner (no workdir support today)
- `internal/commands/runner_service.go` — service runners (`buildDockerComposeCmd`)
- `internal/commands/runner.go` — `RunContext`, dispatch
- `internal/commands/types_test.go`, `runner_*_test.go` — affected unit tests
- `internal/command/command_cmd.go`, `internal/command/docs.go` —
  `commands inspect` and `docs generate` formatters that print `cwd:` today
- `internal/condition/condition.go`, `internal/tpl/engine.go` — reused unchanged
  for workflow `when` evaluation (same `IsRuntime`/`EvalRuntime`/`EvalCondition`
  flow used by deploy/lifecycle)

**Pilot repo (this checkout):**

- `CLAUDE.md` — Phase 4 / commands documentation paragraphs
- `devbox/commands/**/*.yml` — opportunistic demos for each new mechanism
  (no `cwd:` exists today, so removing it costs no migrations)
- `docs/reference/commands/*.md` — regenerated via `devbox docs generate`

### Related patterns found

- **`when` evaluation — diverges from the deploy/lifecycle pattern.** The
  pipeline path uses `tpl.EvalCondition(s, cfg)` (which only understands Go
  templates `{{ }}` against `DevboxConfig`) and `condition.EvalRuntime(s,
  workDir)` directly. **Commands use a different template surface**:
  `${param.*}`, `${context.*}`, `${files.*}`, `${host.*}`, `${dot.path}`
  resolved via `tpl.RenderCommand(s, *RenderContext)`. Calling
  `tpl.EvalCondition` against `ctx.Config` would silently fail to expand
  `${...}` and would route `{{ .Params.x }}` against the wrong data shape.
  Calling `condition.EvalRuntime` on an unrendered string would execute
  predicates like `dir-empty ${param.path}` or `cmd: test -f
  ${files.dump.path}` with literal `${...}` text. Workflow `when` therefore
  needs a **render-first** evaluator. See Technical Details for the dispatch.
- **`continue_on_error` pattern** — `config.DeployStep.ContinueOnError` is
  honored in `internal/command/pipeline.go:516`–`518`. Workflow steps adopt the
  same field name and the same "report the error, then keep going" semantics
  (no Check/post-step hook to skip — workflow steps don't have those).
- **Template resolution** — `tpl.RenderCommand` is already used for `cmd.Run`,
  `cmd.Argv[i]`, `cmd.Cwd`, env values; `compose_args[i]` slots in identically.
- **Service compose argv assembly** — `buildDockerComposeCmd` in
  `runner_service.go:193` is the single place that orders `[project, files,
  global_args, exec|run, command_defaults, --no-deps --entrypoint "" (run only),
  --user, --workdir, -e KEY=VAL..., service, serviceArgv...]`. `compose_args`
  inserts immediately **after `command_defaults`** (and the run-only
  `--no-deps --entrypoint ""`) and **before `--user`**.

### Dependencies identified

- No new external Go dependencies.
- `internal/condition` and `internal/tpl` are already imported by command-level
  code paths (deploy/reset/lifecycle); workflow runner will start importing
  them.

## Development Approach

- **Testing approach**: Regular (code first, then tests) — the user did not
  indicate a TDD preference and this is a small set of focused additions to a
  well-tested package.
- **Repository discipline**: every Go change is committed inside `devbox-cli/`
  as a separate commit. The pilot repo gets at most one final commit per
  mechanism for YAML demos / CLAUDE.md updates. Do **not** create pilot-repo
  commits that depend on uncommitted devbox-cli work.
- **Commit boundaries**: each Task below ends with two commits maximum: one in
  `devbox-cli/`, optionally one in the pilot repo if YAML/docs were updated.
- Complete each task fully before moving to the next.
- **CRITICAL: every task MUST include new/updated tests** for code changes in
  that task — both success and failure paths.
- **CRITICAL: all tests must pass before starting next task** — run
  `cd devbox-cli && make test && make lint` after each task; pilot-repo
  validation is `./bin/devbox commands list` plus inspecting any modified
  command (`./bin/devbox commands inspect <id>`).
- **CRITICAL: update this plan file when scope changes during implementation.**
- Maintain backward compatibility for the YAML surface **except** for the
  intentional `cwd` removal (Task 4) — verified above to be unused in the
  current pilot repo.

## Testing Strategy

- **Unit tests**: required for every task in `devbox-cli/internal/commands/`
  and (for output formatters) `devbox-cli/internal/command/`. Cover both
  rendering/validation success paths and error/edge cases.
- **Integration check**: rebuild the binary (`cd devbox-cli && make build`),
  then exercise the changed mechanism in the pilot repo with
  `./bin/devbox commands run <id>` against a representative YAML demo.
- **Regression**: `make test` and `make lint` in `devbox-cli/` after each
  task — do not advance with red builds.
- No e2e/UI tests in this repo; skip that strategy step.

## Progress Tracking

- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Update plan if implementation deviates from original scope
- Keep plan in sync with actual work done

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): code changes, unit tests, doc
  regeneration, CLAUDE.md edits, demo YAML — everything an agent can do
  inside this checkout.
- **Post-Completion** (no checkboxes): manual smoke runs, pushing the
  devbox-cli branch, opening pull requests on either repo.

## Implementation Steps

### Task 1: Add `when` and `continue_on_error` to workflow steps

Touches `devbox-cli/internal/commands/` and `devbox-cli/internal/tpl/`.
Single devbox-cli commit at the end.

- [x] extend `WorkflowStep` in `internal/commands/types.go` with
      `When string \`yaml:"when"\`` and `ContinueOnError bool \`yaml:"continue_on_error"\``
- [x] update `WorkflowStep.Validate`: allow `when` on either command-step or
      confirm-step; reject `continue_on_error` on confirm steps (a confirm
      that can be ignored is meaningless); keep current command/confirm
      mutual exclusion
- [x] add a new helper `tpl.EvalCommandCondition(expr string, ctx
      *RenderContext, projectRoot string) (bool, error)` in
      `internal/tpl/render_command.go`:
      - empty `expr` → `true, nil`
      - render via `RenderCommand(expr, ctx)` so `${...}` / `{{ }}` resolve
        against the command surface (params/context/files/host/raw)
      - re-classify the **rendered** text via `condition.Classify`:
        - `KindCmd` → `condition.EvalCmd(payload, projectRoot)`
        - `KindBuiltin` → **literal-boolean fast path first**: when the
          trimmed payload is one of the recognised boolean tokens —
          `""`, `"true"`, `"1"` (truthy) or `"false"`, `"0"` (falsy) —
          return the corresponding bool. **Any other value** (including
          looks-like-a-predicate strings such as `dir-emty foo` or
          `file-exist services/main/src`) is forwarded to
          `condition.EvalBuiltin`, which surfaces a wrapped error for
          unknown verbs or malformed predicates. This preserves the
          deploy/lifecycle behavior of failing loudly on typos rather
          than silently truthy-fying them.
        - `KindTemplate` is unreachable after `RenderCommand` (no `{{ }}`
          remain), but defend against it by applying the same
          literal-boolean rule and otherwise returning a wrapped error
          (`"eval when %q: unexpected residual template"`)
      - return wrapped errors prefixed with `"eval when %q"`
- [x] write unit tests for `EvalCommandCondition` in
      `tpl/render_command_test.go`:
      - empty expr → true
      - `${param.x}` → bool, with x ∈ {`"1"`, `"true"`} truthy and
        x ∈ {`"0"`, `"false"`, `""`} falsy
      - `${...}` inside a `cmd:` predicate (e.g.
        `cmd: test -f ${files.dump.path}`) substitutes before exec; assert
        truthy/falsy by toggling the file's existence
      - `${...}` inside a known builtin (`dir-empty
        services/${param.svc}/src`) substitutes and dispatches to
        `EvalBuiltin`
      - render error (e.g. unresolvable `${missing.key}`) surfaces a
        wrapped error
      - **malformed known builtin** (e.g. `dir-empty` with no path)
        surfaces the `EvalBuiltin` parse error, wrapped
      - **typo on a builtin verb** (e.g. `dir-emty foo`,
        `file-exist services/main/src`) surfaces an `EvalBuiltin`
        unknown-verb error, wrapped — must NOT silently return true
- [x] in `runner_workflow.go`, before dispatching each step (both command
      and confirm branches), call `tpl.EvalCommandCondition(step.When,
      ctx.Render, ctx.ProjectRoot)` when `step.When != ""`; on error
      return wrapped; on false log `"  ◎ workflow %q step[%d]: skipped
      (when: %s)\n"` to stderr and `continue`
- [x] in `runCommandStep` (and the confirm path where applicable), wrap the
      terminal `RunCommand`/confirm error: when `step.ContinueOnError` is
      true and the underlying error is non-nil, print a warning to stderr
      (format `"workflow %q step[%d] %q: continue_on_error: %v"`) and return
      nil so the loop proceeds; when false, keep current behavior
- [x] do not change the public `RunContext` shape
- [x] write tests in `runner_workflow_test.go` covering: truthy
      `${param.*}` `when` runs, falsy `${param.*}` `when` skips, runtime
      `when` (`cmd: true` / `cmd: false`) executes against `ctx.ProjectRoot`,
      `${...}` is substituted inside `cmd:` (assert via a temp file
      probe), invalid `when` expression surfaces wrapped error,
      command-step failure with `continue_on_error: true` returns nil +
      writes warning, command-step failure without `continue_on_error`
      still aborts, `continue_on_error` on confirm step rejected by
      `Validate`
- [x] add a parsing test in `types_test.go` confirming both new fields
      round-trip through YAML
- [x] run `cd devbox-cli && make test && make lint` — must be green before
      committing
- [x] commit in `devbox-cli/`:
      `feat(commands): support when and continue_on_error on workflow steps`

### Task 2: Add `compose_args` to service_exec / service_run

Touches `devbox-cli/internal/commands/` and the inspect/docs formatters.

- [x] add `ComposeArgs []string \`yaml:"compose_args"\`` to `CommandDef`
      in `internal/commands/types.go`
- [x] in `CommandDef.Validate`: reject `compose_args` for any type other
      than `service_exec` / `service_run` (call from
      `validateCommandType`, `validateScriptType`, `validateWorkflowType` —
      pattern matches existing field-by-type checks)
- [x] in `runner_service.go`, render every `cmd.ComposeArgs[i]` through
      `tpl.RenderCommand` using `ctx.Render`; collect into a `[]string`
      slice; surface render errors with the
      `"render compose_args[%d]: %w"` pattern
- [x] thread the rendered slice into `buildDockerComposeCmd` (new parameter
      `composeArgs []string`); insert after the
      `compose.CommandArgs[exec|run]` defaults and (for `run`) the
      `--no-deps --entrypoint ""` block, **before** the `--user` / `--workdir`
      / `-e` block; preserve order
- [x] update the inspect formatter (`internal/command/command_cmd.go`)
      and docs formatter (`internal/command/docs.go`) so non-empty
      `compose_args` is emitted as a list (mirror how `argv` / `env` are
      printed today)
- [x] write tests in `runner_service_test.go` for `service_exec` and
      `service_run` covering: empty `compose_args` is a no-op (current
      argv unchanged); literal args are inserted at the documented
      position relative to `--user`/`--workdir`/`-e`; templates are
      rendered (`-e KEY=${param.x}` round-trip) using a fixture similar
      to the existing tests; render error surfaces a wrapped error;
      validation rejects `compose_args` on `command`, `script`, and
      `workflow` types
- [x] add a YAML round-trip test in `types_test.go` for `compose_args`
- [x] run `cd devbox-cli && make test && make lint` — must be green
- [x] commit in `devbox-cli/`:
      `feat(commands): allow compose_args on service_exec/service_run`

### Task 3: Support `workdir` for type=script (host-side)

Touches `devbox-cli/internal/commands/runner_script.go` and tests. Validation
already permits `workdir` on script (it's currently silently ignored), but we
codify allowed types in Task 4.

- [x] in `ScriptRunner.execScript`, after rendering, if `ctx.Cmd.Workdir` is
      non-empty: render it via `tpl.RenderCommand`, normalize relative
      paths against `ctx.ProjectRoot`, set `c.Dir = rendered`. Otherwise
      retain the current `c.Dir = ctx.ProjectRoot` default.
- [x] keep `scriptPath` resolution untouched: `script.path` is **always**
      resolved against `ctx.ProjectRoot` (not against the new `workdir`).
      Add a doc comment in `runner_script.go` calling this out.
- [x] write tests in `runner_script_test.go`: absolute `workdir` honored,
      relative `workdir` resolved against project root, `script.path`
      remains project-root-relative even when `workdir` is set, render
      error in `workdir` template surfaces a wrapped error, missing
      `workdir` falls back to project root (regression check)
- [x] run `cd devbox-cli && make test && make lint` — must be green
- [x] commit in `devbox-cli/`:
      `feat(commands): apply workdir to script runner`

### Task 4: Remove `cwd`, unify on `workdir` for host commands

Removes the `Cwd` field entirely. Verified that no current YAML uses `cwd:`,
so this is a clean break, not a deprecation.

- [x] delete `Cwd string \`yaml:"cwd"\`` from `CommandDef` in
      `internal/commands/types.go`
- [x] in `runner_host.go` `BuildCommand`: replace `cmd.Cwd` references with
      `cmd.Workdir`; render via `tpl.RenderCommand`; relative paths resolve
      against `ctx.ProjectRoot`; absolute paths used as-is; empty falls
      back to `c.Dir = ctx.ProjectRoot`
- [x] extend `CommandDef.Validate` — note: `workdir_from` is currently
      *silently ignored* outside service runners (no validation rejects
      it today). This task tightens the rules:
      - `workdir` allowed on: `command`, `script`, `service_exec`,
        `service_run`
      - `workdir` rejected on: `workflow`, `devbox`
      - `workdir_from` allowed on: `service_exec`, `service_run` only
      - `workdir_from` **explicitly rejected** on: `command`, `script`,
        `workflow`, `devbox` (new check — was previously ignored)
      - update `validateCommandType`, `validateScriptType`,
        `validateWorkflowType`; add the `workflow`/`devbox` rejection for
        `workdir` in `validateWorkflowType` and the corresponding `devbox`
        path in `validateCommandType` (which today already routes
        `CommandTypeDevbox` through it)
- [x] update inspect (`command_cmd.go`) and docs (`docs.go`) formatters:
      remove the `cwd` branch; print `workdir` for any command type that
      sets it (already happens for service types; just generalize)
- [x] update affected tests: rename `Cwd` → `Workdir` in
      `runner_host_test.go` (`TestHostRunner_BuildCommand_CwdAbsolute` and
      siblings), `types_test.go` (`cwd: /var/www/html` fixture), and any
      other call sites flagged by `go build`
- [x] add new tests in `runner_host_test.go`: `workdir` on
      `type: command` (absolute + relative + template render error);
      validation rejects `workdir` on `type: workflow` and `type: devbox`;
      validation accepts `workdir` on all other types
- [x] add validation tests in `types_test.go`: `workdir_from` rejected on
      `type: command`, `type: script`, `type: workflow`, `type: devbox`;
      `workdir_from` accepted on `service_exec` and `service_run`
- [x] run `cd devbox-cli && make test && make lint` — must be green
- [x] commit in `devbox-cli/`:
      `refactor(commands)!: replace cwd with workdir on host commands`
      (bang because the YAML key is removed)

### Task 5: Update CLI documentation and demos in the pilot repo

Touches the pilot repo only (single commit). All Go changes already shipped
in Tasks 1–4.

- [x] rebuild `./bin/devbox` (`cd devbox-cli && make build`)
- [x] update `CLAUDE.md`: extend the Phase 4 / commands paragraphs to
      describe workflow `when` + `continue_on_error`, `compose_args` for
      service runners, and the unified `workdir` semantics (note: `cwd`
      removed, `script.path` is always project-root-relative). Also added
      new "Commands System Features" subsection with detailed docs.
- [x] regenerate command reference: `./bin/devbox docs generate`
- [x] skip demos — analyzed all existing commands; none genuinely benefit
      from the new mechanisms. Unit tests from Tasks 1–4 provide thorough
      coverage:
      - workflow `when` / `continue_on_error` — all steps in existing
        workflows (db.start, services.main.bootstrap) are mandatory
      - `compose_args` — no current service commands need non-default flags
      - `workdir` for host/script — dump-create script doesn't require
        workdir; script.path already project-root-relative
- [x] verify with `./bin/devbox commands list` and
      `./bin/devbox commands inspect <id>` — all commands display correctly;
      bootstrap workflow, db.create, dump-create inspected successfully
- [x] commit in pilot repo:
      `feat: workflow conditions, compose_args, unified workdir` (commit 0f5de5d)

### Task 6: Verify acceptance criteria

- [ ] verify all three mechanisms from Overview are implemented with the
      promised semantics
- [ ] verify `cwd` is gone from the YAML schema and Go struct
- [ ] verify `workdir_from` is **not** newly accepted on host/script
- [ ] run full devbox-cli test suite (`make test`) and linter (`make lint`)
- [ ] verify test coverage on touched files is ≥ existing baseline (no
      regressions in coverage report)
- [ ] confirm both repos have clean working trees before
      announcing the plan complete

## Technical Details

### Workflow `when` evaluation

Workflows operate in command-template space (`${param.*}`,
`${context.*}`, `${files.*}`, `${host.*}`, `${dot.path}`), not the
deploy-config Go-template space (`{{ .Foo }}` against `DevboxConfig`).
Evaluation must therefore **render first, then classify**, otherwise:

- `tpl.EvalCondition` would silently skip `${...}` (its `Render`
  short-circuits when the string contains no `{{`), so
  `when: "${param.queue}"` is never expanded.
- `condition.EvalRuntime` would execute predicates with literal
  `${...}` text, e.g. `cmd: test -f ${files.dump.path}` would shell out
  with the placeholder still in place.

Add a single helper in `tpl` and use it from the workflow runner:

```go
// internal/tpl/render_command.go
func EvalCommandCondition(expr string, ctx *RenderContext, projectRoot string) (bool, error) {
    if expr == "" {
        return true, nil
    }
    rendered, err := RenderCommand(expr, ctx) // resolves ${...} and {{ }}
    if err != nil {
        return false, fmt.Errorf("eval when %q: %w", expr, err)
    }
    kind, payload := condition.Classify(rendered)
    switch kind {
    case condition.KindCmd:
        return condition.EvalCmd(payload, projectRoot)
    case condition.KindBuiltin:
        // After rendering, payload is either a boolean literal produced
        // by ${param.*} / ${context.*} substitution, or a predicate
        // string. Resolve literals up front; everything else goes to
        // EvalBuiltin so unknown verbs and malformed predicates fail
        // loudly (matching deploy/lifecycle semantics).
        switch strings.TrimSpace(payload) {
        case "", "false", "0":
            return false, nil
        case "true", "1":
            return true, nil
        default:
            return condition.EvalBuiltin(payload, projectRoot)
        }
    default: // KindTemplate — unreachable post-render.
        return false, fmt.Errorf("eval when %q: unexpected residual template", expr)
    }
}
```

```go
// internal/commands/runner_workflow.go
if step.When != "" {
    ok, err := tpl.EvalCommandCondition(step.When, ctx.Render, ctx.ProjectRoot)
    if err != nil {
        return fmt.Errorf("workflow %q step[%d]: %w", ctx.Cmd.ID, i, err)
    }
    if !ok {
        fmt.Fprintf(stderr(ctx), "  ◎ workflow %q step[%d]: skipped (when: %s)\n",
            ctx.Cmd.ID, i, step.When)
        continue
    }
}
```

No verb whitelist is maintained in `tpl` — `condition.EvalBuiltin`
already owns the canonical verb table and produces a useful error for
unknowns (`unknown builtin predicate %q`). Forwarding everything that
isn't a literal boolean keeps the two packages decoupled and avoids a
second source of truth that could drift if new verbs are added.

### `compose_args` insertion order

```
docker compose
  -p <project>
  -f <file>...
  <global_args from policy>
  exec | run
  <CommandArgs[exec|run] from policy>
  [run only: --no-deps --entrypoint ""]
  <compose_args from CommandDef, rendered>   ← NEW
  --user <UID:GID|root|literal>
  --workdir <path>
  -e KEY=VAL ...
  <service>
  <serviceArgv...>
```

### Field validity matrix after Task 4

| field          | command | script | service_exec | service_run | workflow | devbox |
| -------------- | :-----: | :----: | :----------: | :---------: | :------: | :----: |
| `workdir`      |   ✓    |   ✓   |      ✓      |      ✓     |    ✗    |   ✗   |
| `workdir_from` |   ✗    |   ✗   |      ✓      |      ✓     |    ✗    |   ✗   |
| `compose_args` |   ✗    |   ✗   |      ✓      |      ✓     |    ✗    |   ✗   |
| `cwd`          |   removed everywhere                                          |

The ✗ cells for `workdir_from` are **newly enforced** in Task 4. Today
those cells are silently ignored — the field exists on `CommandDef` but
is only consumed by `resolveServiceFields`. Tightening validation
makes the matrix true and prevents future copy-paste mistakes.

### Repository / commit topology

- Tasks 1–4 each produce one commit in the **devbox-cli** repo (separate
  remote). They are independent and can ship as separate PRs there.
- Task 5 produces one commit in the **pilot repo** that updates
  `CLAUDE.md`, regenerated docs under `docs/reference/commands/`, and any
  demo YAML.
- Do not author a pilot-repo commit that references behavior from a
  devbox-cli change that is not yet committed (and ideally pushed) on
  that side, since the pilot repo gitignores the CLI source.

## Post-Completion

**Manual verification:**

- Run a workflow with a falsy `when` step against a fresh checkout to
  confirm the skip log line is emitted and the workflow continues.
- Run a workflow with a deliberately failing `continue_on_error: true`
  step (e.g. `command: log.clean` against a missing path) and confirm
  the warning is printed and subsequent steps still execute.
- Invoke a `service_run` command that uses `compose_args: ["-d", "--name",
  "..."]` and confirm `docker compose run` receives the flags in the
  documented position via `docker compose run --dry-run` or a `compose
  argv` inspection.
- Run a `type: script` command with a relative `workdir` and confirm the
  script's `pwd` matches the resolved directory while `$0` (script path)
  remains project-root-relative.

**External system updates:**

- Push the devbox-cli branch and open a PR on
  `github.com/semsemyonoff/devbox-next-cli`.
- After it merges, push the pilot-repo branch and open the matching PR
  on this repository.
- Tag a new devbox-cli release if downstream consumers (other devbox
  pilots) depend on a versioned binary.
