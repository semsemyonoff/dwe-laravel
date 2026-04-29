# db.dump-create

Create a database dump file

## Properties

| Property | Value |
|---|---|
| **ID** | `db.dump-create` |
| **Type** | `script` |
| **Group** | `db` |
| **Success message** | Database dump created at ${files.dump.path} |
| **Error message** | Failed to create database dump |

**Shell:** `sh`

**Script:** `devbox/scripts/db/dump-create.sh`

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `database` | `string` |  | from `db.database` | Database name to dump |
| `dump_date` | `bool` |  | true | Include date suffix in filename |
| `dump_dir` | `string` |  | from `db.backup_dir` | Directory to store the dump file |

## Environment Variables

| Name | Value |
|---|---|
| `DB_NAME` | `${param.database}` |
| `DB_PASSWORD` | `${db.password}` |
| `DB_USER` | `${db.user}` |

