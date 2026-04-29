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

**Shell:** `bash`

**Script:** `devbox/scripts/db/dump-create.sh`

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `database` | `string` |  | from `db.database` | Database name to dump |
| `dump_date` | `bool` |  | true | Include date suffix in filename |
| `dump_dir` | `string` | yes | from `db.backup_dir` | Directory to store the dump file |

## Files

### `dump` (write)

**Env:** `DUMP_FILE`

**Path:** `${param.dump_dir}/${param.database}{{ if .Params.dump_date }}_{{ date }}{{ end }}.sql.gz`

## Environment Variables

| Name | Value |
|---|---|
| `DB_NAME` | `${param.database}` |
| `DB_USER` | `${db.user}` |
| `MYSQL_PWD` | `${db.password}` |

