#!/bin/bash
set -euo pipefail

# Restore a database from a dump file.
# Uses DEVBOX_BIN to invoke commands consistently.
# Dump file path is resolved by the files directive and provided via DUMP_FILE.
# Target database name is provided via TARGET_DB_NAME.

# Optional: check if target database exists before dropping
if [ "$CHECK_EXISTS" = "1" ]; then
  # Capture db list separately so mariadb errors (auth failure, container down)
  # are not silently treated as "database not found".
  db_list=$("$DEVBOX_BIN" docker exec -T -e MYSQL_PWD="$DB_PASSWORD" db -- mariadb \
    -u"$DB_USER" -Nse "SHOW DATABASES" 2>&1) || {
    echo "Failed to query databases: $db_list"
    exit 1
  }
  echo "$db_list" | grep -qxF "$TARGET_DB_NAME" || {
    echo "Target database $TARGET_DB_NAME does not exist. Skipping restore."
    exit 0
  }
fi

# Drop the target database (non-interactive via --yes)
"$DEVBOX_BIN" commands run db.drop --set database="$TARGET_DB_NAME" --yes

# Recreate the target database (non-interactive via --yes)
"$DEVBOX_BIN" commands run db.create --set database="$TARGET_DB_NAME" --yes

# Restore from dump file
gunzip -c "$DUMP_FILE" | "$DEVBOX_BIN" docker exec -T -e MYSQL_PWD="$DB_PASSWORD" db -- \
  mariadb -u"$DB_USER" -D "$TARGET_DB_NAME"
