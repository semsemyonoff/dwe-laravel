# db.cli

Connect to the database in the db container

## Properties

| Property | Value |
|---|---|
| **ID** | `db.cli` |
| **Type** | `service_exec` |
| **Group** | `db` |

**Service:** `db`

## Command

```sh
mariadb -u${db.user} {{with .Params.database}} -D{{.}}{{end}}
```

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `database` | `string` |  |  | Database name to connect |

## Environment Variables

| Name | Value |
|---|---|
| `MYSQL_PWD` | `${db.password}` |

