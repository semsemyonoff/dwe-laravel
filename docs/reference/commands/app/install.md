# app.install

Install the Laravel application via installer container

## Properties

| Property | Value |
|---|---|
| **ID** | `app.install` |
| **Type** | `devbox` |
| **Group** | `app` |

## Command

```sh
compose raw --bare -- --progress tty -f compose/installer.yml run --rm --quiet-pull -u ${host.uid}:${host.gid} app-install
```

