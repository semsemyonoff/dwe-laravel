#!/bin/bash
set -euo pipefail

# Create a database dump using mariadb-dump and compress it with gzip.
# Uses DEVBOX_BIN to invoke docker commands consistently.
# Destination path is provided via DUMP_FILE (resolved and set by files directive).
#
# Write to a temp file and atomically rename on success so that an existing
# dump at the same path is never truncated or corrupted if the dump fails.

TMPFILE=$(mktemp "${DUMP_FILE}.XXXXXX")
trap 'rm -f "$TMPFILE"' EXIT

"$DEVBOX_BIN" docker exec -T db -- mariadb-dump \
  -u"$DB_USER" "$DB_NAME" --no-create-db --no-tablespaces | gzip > "$TMPFILE"
mv "$TMPFILE" "$DUMP_FILE"
