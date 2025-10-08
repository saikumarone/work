#!/bin/bash

# Usage: ./get_table_counts.sh <ssh_user> <host> <db_name> <output_file>
# Example: ./get_table_counts.sh postgres 192.168.1.10 mydb counts.txt

SSH_USER=$1
HOST=$2
DB_NAME=$3
OUTPUT_FILE=$4

if [ $# -ne 4 ]; then
  echo "Usage: $0 <ssh_user> <host> <db_name> <output_file>"
  exit 1
fi

# Temporary SQL file to list tables
SQL_FILE="/tmp/list_tables.sql"

cat <<EOF > $SQL_FILE
SELECT table_schema || '.' || table_name AS full_table_name
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
  AND table_catalog = '${DB_NAME}'
  AND table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast', 'pglogical')
  AND (table_schema || '.' || table_name) NOT IN (
      'public.audit_log',
      'public.temp_data',
      'market_data.snap'
  )
ORDER BY table_schema, table_name;
EOF

# Execute the SQL on remote host to get the list of tables
echo "Fetching table list from ${DB_NAME} on ${HOST}..."
TABLES=$(ssh ${SSH_USER}@${HOST} "psql -d ${DB_NAME} -At -f -" < $SQL_FILE)

if [ -z "$TABLES" ]; then
  echo "No tables found or connection failed."
  exit 1
fi

echo "Writing table counts to ${OUTPUT_FILE}..."
echo "=========== TABLE COUNTS (${DB_NAME}) ===========" > ${OUTPUT_FILE}

# Loop through each table and get count
for TABLE in $TABLES; do
  COUNT=$(ssh ${SSH_USER}@${HOST} "psql -d ${DB_NAME} -At -c \"SELECT COUNT(*) FROM $TABLE;\"" 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "$TABLE | $COUNT" >> ${OUTPUT_FILE}
  else
    echo "$TABLE | ERROR" >> ${OUTPUT_FILE}
  fi
done

echo "==================================================" >> ${OUTPUT_FILE}
echo "Done! Results stored in ${OUTPUT_FILE}"
