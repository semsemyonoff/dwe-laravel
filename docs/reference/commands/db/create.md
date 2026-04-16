# db.create

Create a database in the db container

## Properties

| Property | Value |
|---|---|
| **ID** | `db.create` |
| **Type** | `service_exec` |
| **Group** | `db` |
| **Private** | yes |

**Service:** `db`

## Command

```sh
mariadb -u${db.user} -e 'CREATE DATABASE IF NOT EXISTS `${param.database}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'
```

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `database` | `string` | yes |  | Database name to create |

## Environment Variables

| Name | Value |
|---|---|
| `MYSQL_PWD` | `${db.password}` |

