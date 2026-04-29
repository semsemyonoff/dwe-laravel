#!/bin/bash
set -eu

# Create a database dump using mariadb-dump and compress it with gzip.
# Uses DEVBOX_BIN to invoke docker commands consistently.
# Destination path is provided via DUMP_FILE (resolved and set by files directive).

MYSQL_PWD="$DB_PASSWORD" "$DEVBOX_BIN" docker exec -T db -- mariadb-dump \
  -u"$DB_USER" "$DB_NAME" | gzip > "$DUMP_FILE"
