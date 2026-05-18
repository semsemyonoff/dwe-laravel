# Local IDE template overrides

This directory is an **example** of a per-file local override for the `ide/default`
template pack. To activate it, copy this tree to a sibling directory named
`default.local/` (gitignored):

```sh
cp -r devbox/templates/ide/default.local.example devbox/templates/ide/default.local
```

## How resolution works

When `devbox render ide` reads a template file declared in
`devbox/templates/ide/default/manifest.yml`, it first checks the same relative
path under `devbox/templates/ide/default.local/`:

- file present at the local path → that file is used and the renderer prints
  `using local override: devbox/templates/ide/default.local/<rel>`
- file missing → the canonical `default/<rel>` template is used

The `manifest.yml` itself is read **only** from the canonical pack — a local
override cannot rewrite the manifest, only substitute individual `from:` sources.
Only include the files you want to override; this is not a full pack.

## Caveats

- The rendered output still lands at the manifest-declared `to` (e.g.
  `services/<svc>/.vscode/settings.json`), which is typically tracked. Re-running
  `devbox render ide` will modify those files — keep the changes out of commits
  the same way you would keep any other personal WIP edit out.
- A `default.local/` entry that exists as a directory or symlink is a hard error
  rather than a silent fall-through, so a broken override surfaces itself.
