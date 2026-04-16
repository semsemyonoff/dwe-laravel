# db.start

Start the database container and wait until healthy

## Properties

| Property | Value |
|---|---|
| **ID** | `db.start` |
| **Type** | `workflow` |
| **Group** | `db` |
| **Private** | yes |

## Steps

1. `db.up`
2. `db.wait`

