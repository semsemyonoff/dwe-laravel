# db.dump-deploy

Restore a database from a dump file

## Properties

| Property | Value |
|---|---|
| **ID** | `db.dump-deploy` |
| **Type** | `script` |
| **Group** | `db` |
| **Success message** | Database restored from ${files.dump.path} |
| **Error message** | Failed to restore database |

**Shell:** `sh`

**Script:** `devbox/scripts/db/dump-deploy.sh`

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `check_exists` | `bool` |  | false | Check if target database exists before restore |
| `database` | `string` |  | from `db.database` | Source database (for backup reference, if needed) |
| `dump_dir` | `string` |  | from `db.backup_dir` | Directory containing dump files |
| `target_database` | `string` | yes |  | Target database to restore to |

## Environment Variables

| Name | Value |
|---|---|
| `CHECK_EXISTS` | `{{ if .Params.check_exists }}1{{ else }}0{{ end }}` |
| `DB_NAME` | `${param.database}` |
| `DB_PASSWORD` | `${db.password}` |
| `DB_USER` | `${db.user}` |
| `TARGET_DB_NAME` | `${param.target_database}` |

