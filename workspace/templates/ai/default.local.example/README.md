# Local AI template overrides

This directory is an **example** of a per-file local override for the `ai/default`
template pack. To activate it, copy this tree to a sibling directory named
`default.local/` (gitignored):

```sh
cp -r workspace/templates/ai/default.local.example workspace/templates/ai/default.local
```

## How resolution works

When `dwe render ai` reads a template file declared in
`workspace/templates/ai/default/manifest.yml`, it first checks the same relative
path under `workspace/templates/ai/default.local/`:

- file present → that file is used and the renderer prints
  `using local override: workspace/templates/ai/default.local/<rel>`
- file missing → the canonical `default/<rel>` template is used

The `manifest.yml` itself is read **only** from the canonical pack — a local
override cannot rewrite render entries or symlinks, only substitute the source
templates they reference. Only include the files you want to override.

## Caveats

- The rendered output still lands at the manifest-declared `to` (e.g.
  `services/<svc>/AGENTS.md`), which is typically tracked. Re-running
  `dwe render ai` will modify those files — keep the changes out of commits
  the same way you would keep any other personal WIP edit out.
- A `default.local/` entry that exists as a directory or symlink at a render
  source path is a hard error rather than a silent fall-through.
