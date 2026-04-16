# services.second.bootstrap

Full bootstrap — start db, create database, install deps, generate key, run migrations

## Properties

| Property | Value |
|---|---|
| **ID** | `services.second.bootstrap` |
| **Type** | `workflow` |
| **Group** | `services.second` |

## Steps

1. `db.start`
2. `services.second.db.create`
3. `services.second.composer-install`
4. `services.second.key-generate`
5. `services.second.migrate`

