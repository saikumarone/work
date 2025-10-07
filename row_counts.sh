#!/usr/bin/env bash
set -euo pipefail

# ===========================================
# Count rows in all non-system PostgreSQL tables on a remote host
# ===========================================

# ----------------------------
# Hardcoded configuration
# ----------------------------
SSH_USER="ubuntu"                    # SSH user (e.g., ubuntu, root)
SSH_PORT="22"                        # SSH port
HOST="192.168.56.10"                 # Remote host
DB_NAME="postgres"                   # Database name
EXCLUDE_FILE="/tmp/exclude.txt"      # Optional exclude file path (schema.table per line)
OUTPUT_DIR="outputs"                 # Local directory to save results
SSH_IDENTITY=""                      # Leave empty if ssh-agent handles it; set to /path/to/key if needed
FORCE_TTY=0                          # Set to 1 if sudo requires TTY

# ----------------------------
# Prepare exclusion list
# ----------------------------
EXCLUDE_LIST=""
if [[ -n "${EXCLUDE_FILE}" && -f "$EXCLUDE_FILE" ]]; then
  EXCLUDE_LIST="$(grep -vE '^\s*($|#)' "$EXCLUDE_FILE" | sed 's/[[:space:]]*$//')"
fi

mkdir -p "$OUTPUT_DIR"

# ----------------------------
# SSH options
# ----------------------------
SSH_OPTS=(
  -p "$SSH_PORT"
  -o BatchMode=yes
  -o PreferredAuthentications=publickey
  -o PubkeyAuthentication=yes
  -o StrictHostKeyChecking=accept-new
  -o ControlMaster=auto
  -o ControlPersist=60s
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=4
)
if [[ -n "$SSH_IDENTITY" ]]; then
  SSH_OPTS+=(-i "$SSH_IDENTITY")
fi

SSH_TTY_FLAG=()
if [[ "$FORCE_TTY" -eq 1 ]]; then
  SSH_TTY_FLAG=(-tt)
fi

# ----------------------------
# Remote worker script
# ----------------------------
REMOTE_SCRIPT='
set -euo pipefail

DB_NAME="${DB_NAME:-postgres}"
TmpDir="/tmp"
TmpFile="$TmpDir/psql.$$.$RANDOM.out"

declare -A SKIP=()
if [[ -n "${EXCLUDE_LIST:-}" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="$(echo "$line" | awk "{gsub(/^[ \t]+|[ \t]+$/, \"\"); print}")"
    [[ -z "$key" ]] && continue
    SKIP["$key"]=1
  done <<< "$EXCLUDE_LIST"
fi

psql -d "$DB_NAME" -At -F $'\t' -c "
  SELECT table_schema, table_name
  FROM information_schema.tables
  WHERE table_type = '\''BASE TABLE'\''
    AND table_schema NOT IN ( '\''pg_catalog'\'', '\''pg_toast'\'', '\''information_schema'\'', '\''pglogical'\'' )
  ORDER BY table_schema, table_name;
" > "$TmpFile"

MaxLen=0
while IFS=$'\t' read -r schema table; do
  [[ -z "${schema:-}" || -z "${table:-}" ]] && continue
  fqtn="$schema.$table"
  [[ -n "${SKIP[$fqtn]+x}" ]] && continue
  len=${#fqtn}
  (( len > MaxLen )) && MaxLen=$len
done < "$TmpFile"
((MaxLen++))

echo
echo "Using Database -> $DB_NAME"
echo
echo "Counting table rows ..."
echo

RunTot=0
while IFS=$'\t' read -r schema table; do
  [[ -z "${schema:-}" || -z "${table:-}" ]] && continue
  fqtn="$schema.$table"
  [[ -n "${SKIP[$fqtn]+x}" ]] && continue

  qt="\"$schema\".\"$table\""

  printf "%-${MaxLen}.${MaxLen}s : " "$fqtn"
  result="$(psql -d "$DB_NAME" -AtqX -c "SELECT COUNT(*) FROM $qt;")" || {
    echo "ERROR counting $fqtn" >&2
    exit 1
  }

  result="$(echo "$result" | tr -d "[:space:]")"
  printf "%12d\n" "$result"
  (( RunTot += result ))
done < "$TmpFile"

LineLen=$((MaxLen + 3 + 12))
yes "=" | head -n "$LineLen" | tr -d "\n"
echo
printf "%-${MaxLen}.${MaxLen}s : %12d\n\n" "TOTAL ROWS" "$RunTot"

rm -f "$TmpFile"
'

# ----------------------------
# Execute remotely
# ----------------------------
echo "===> Connecting to host: $HOST"
host_dir="${OUTPUT_DIR}/${HOST}"
mkdir -p "$host_dir"

if ! ssh "${SSH_TTY_FLAG[@]}" "${SSH_OPTS[@]}" "${SSH_USER}@${HOST}" \
    "sudo -u postgres bash -lc 'DB_NAME=\"\$DB_NAME\" EXCLUDE_LIST=\"\$EXCLUDE_LIST\" bash -s'" \
    DB_NAME="$DB_NAME" EXCLUDE_LIST="$EXCLUDE_LIST" \
    <<< "$REMOTE_SCRIPT" \
    | tee "${host_dir}/counts.txt"
then
  echo "ERROR: Remote execution failed on ${HOST}" >&2
  exit 1
fi

echo "✅ Saved results to ${host_dir}/counts.txt"
