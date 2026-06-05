# Local git-hook template overrides

This directory is an **example** of a per-file local override for the `git/default`
template pack. To activate it, copy this tree to a sibling directory named
`default.local/` (gitignored):

```sh
cp -r workspace/templates/git/default.local.example workspace/templates/git/default.local
```

## How resolution works

When `dwe render git` reads a template file declared in
`workspace/templates/git/default/manifest.yml`, it first checks the same relative
path under `workspace/templates/git/default.local/`:

- file present → that file is used and the renderer prints
  `using local override: workspace/templates/git/default.local/<rel>`
- file missing → the canonical `default/<rel>` template is used

The `manifest.yml` itself is read **only** from the canonical pack — overrides
substitute individual `from:` sources, they don't add or remove hooks.
Only include the files you want to override.

## Notes for git packs

- The rendered output lives in `<svc.Dir>/src/.git/hooks/<basename>`, which is
  never tracked by git, so the override is fully private to the developer.
- Re-running `dwe render git` always resets file mode to `0755`.
- `symlinks:` is not supported in git manifests, and `to:` must be a basename.
