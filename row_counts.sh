#!/bin/bash
# Usage: ./get_table_counts_remote.sh <ssh_user> <host> <db_name> <output_file>
# Example: ./get_table_counts_remote.sh ubuntu 10.0.0.12 mydb outputs/mydb_counts.txt
# Requires: passwordless SSH to <ssh_user>@<host>, and sudo access to user 'postgres' on the host.

set -e

SSH_USER=$1
HOST=$2
DB_NAME=$3
OUTPUT_FILE=$4

if [ $# -ne 4 ]; then
  echo "Usage: $0 <ssh_user> <host> <db_name> <output_file>"
  exit 1
fi

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Header line: ============ <log file name without extension> ============
BASE_NAME=$(basename "$OUTPUT_FILE")
LOG_NAME="${BASE_NAME%.*}"
echo "=========== ${LOG_NAME} ===========" > "$OUTPUT_FILE"

# SQL to list (schema|table) for the target DB, excluding system schemas and specific tables
read -r -d '' LIST_SQL <<'SQL'
SELECT table_schema || '|' || table_name
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
  AND table_catalog = current_database()
  AND table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast', 'pglogical')
  AND (table_schema || '.' || table_name) NOT IN (
      'public.audit_log',
      'public.temp_data',
      'market_data.snap'
  )
ORDER BY table_schema, table_name;
SQL

# Fetch the table list by streaming SQL over SSH and sudo-ing to postgres
TABLES=$(
  ssh -o BatchMode=yes "${SSH_USER}@${HOST}" \
    "sudo -Hiu postgres psql -d \"$DB_NAME\" -At -f -" <<< "$LIST_SQL"
)

if [ -z "$TABLES" ]; then
  echo "No tables found or connection failed." | tee -a "$OUTPUT_FILE"
  echo "==================================================" >> "$OUTPUT_FILE"
  exit 1
fi

# Loop through tables and get counts
# We quote identifiers to be safe (\"schema\".\"table\")
while IFS='|' read -r SCHEMA TBL; do
  # Skip empty lines defensively
  [ -z "$SCHEMA" ] && continue
  COUNT=$(
    ssh -o BatchMode=yes "${SSH_USER}@${HOST}" \
      "sudo -Hiu postgres psql -d \"$DB_NAME\" -At -c \"SELECT COUNT(*) FROM \\\"$SCHEMA\\\".\\\"$TBL\\\";\"" 2>/dev/null \
      || echo "ERROR"
  )
  if [[ "$COUNT" =~ ^[0-9]+$ ]]; then
    echo "${SCHEMA}.${TBL} | ${COUNT}" >> "$OUTPUT_FILE"
  else
    echo "${SCHEMA}.${TBL} | ERROR" >> "$OUTPUT_FILE"
  fi
done <<< "$TABLES"

echo "==================================================" >> "$OUTPUT_FILE"
echo "Done. Results saved to: $OUTPUT_FILE"
