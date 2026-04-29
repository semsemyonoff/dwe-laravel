# db.drop

Drop the database in the db container

## Properties

| Property | Value |
|---|---|
| **ID** | `db.drop` |
| **Type** | `service_exec` |
| **Group** | `db` |
| **Confirmation** | yes |
| **Confirmation text** | Are you sure you want to drop the database `${param.database}`? |
| **Success message** | Database `${param.database}` was dropped if it existed. |
| **Error message** | Failed to drop database `${param.database}`. |

**Service:** `db`

## Command

```sh
mariadb -u${db.user} -e 'DROP DATABASE IF EXISTS `${param.database}`;'
```

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `database` | `string` | yes |  | Database name to drop |

## Environment Variables

| Name | Value |
|---|---|
| `MYSQL_PWD` | `${db.password}` |

