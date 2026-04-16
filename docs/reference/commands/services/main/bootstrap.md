# services.main.bootstrap

Full bootstrap — start db, create database, install deps, generate key, run migrations

## Properties

| Property | Value |
|---|---|
| **ID** | `services.main.bootstrap` |
| **Type** | `workflow` |
| **Group** | `services.main` |

## Steps

1. `db.start`
2. `services.main.db.create`
3. `services.main.composer-install`
4. `services.main.key-generate`
5. `services.main.migrate`

