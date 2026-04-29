#!/bin/bash
set -eu

# Restore a database from a dump file.
# Uses DEVBOX_BIN to invoke commands consistently.
# Dump file path is resolved by the files directive and provided via DUMP_FILE.
# Target database name is provided via TARGET_DB_NAME.

# Optional: check if target database exists before dropping
if [ "$CHECK_EXISTS" = "1" ]; then
  MYSQL_PWD="$DB_PASSWORD" "$DEVBOX_BIN" docker exec -T db -- mariadb -u"$DB_USER" -Nse \
    "SHOW DATABASES LIKE '$TARGET_DB_NAME'" | grep -q "$TARGET_DB_NAME" || {
    echo "Target database $TARGET_DB_NAME does not exist. Skipping drop step."
    return 0
  }
fi

# Drop the target database (non-interactive via --yes)
"$DEVBOX_BIN" commands run db.drop --set database="$TARGET_DB_NAME" --yes

# Recreate the target database (non-interactive via --yes)
"$DEVBOX_BIN" commands run db.create --set database="$TARGET_DB_NAME" --yes

# Restore from dump file
gunzip -c "$DUMP_FILE" | MYSQL_PWD="$DB_PASSWORD" "$DEVBOX_BIN" docker exec -T db -- \
  mariadb -u"$DB_USER" -D "$TARGET_DB_NAME"
