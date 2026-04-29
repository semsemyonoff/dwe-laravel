#!/bin/bash
set -euo pipefail

# Restore a database from a dump file.
# Uses DEVBOX_BIN to invoke commands consistently.
# Dump file path is resolved by the files directive and provided via DUMP_FILE.
# Target database name is provided via TARGET_DB_NAME.

# Optional: check if target database exists before dropping
if [ "$CHECK_EXISTS" = "1" ]; then
  # Capture db list (stdout only); stderr goes to a temp file so that mariadb
  # warning/error lines cannot falsely match as a database name in the grep.
  _stderr_file=$(mktemp)
  trap 'rm -f "$_stderr_file"' EXIT
  db_list=$("$DEVBOX_BIN" docker exec -T db -- mariadb \
    -u"$DB_USER" -p"$DB_PASSWORD" -Nse "SHOW DATABASES" 2>"$_stderr_file") || {
    echo "Failed to query databases: $(cat "$_stderr_file")"
    exit 1
  }
  echo "$db_list" | grep -qxF "$TARGET_DB_NAME" || {
    echo "Target database $TARGET_DB_NAME does not exist." >&2
    exit 1
  }
fi

# Drop the target database (non-interactive via --yes)
"$DEVBOX_BIN" commands run db.drop --set database="$TARGET_DB_NAME" --yes

# Recreate the target database (non-interactive via --yes)
"$DEVBOX_BIN" commands run db.create --set database="$TARGET_DB_NAME" --yes

# Restore from dump file
gunzip -c "$DUMP_FILE" | "$DEVBOX_BIN" docker exec -T db -- \
  mariadb -u"$DB_USER" -p"$DB_PASSWORD" -D "$TARGET_DB_NAME"
