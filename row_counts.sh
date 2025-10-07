#!/usr/bin/env bash
set -euo pipefail

# ===========================================
# Count rows in all non-system PostgreSQL tables on a remote host
# Passwordless SSH assumed. Values are hardcoded here.
# ===========================================

# ----------------------------
# Hardcoded configuration (edit these)
# ----------------------------
SSH_USER="ubuntu"                    # SSH user (e.g., ubuntu, root)
SSH_PORT="22"                        # SSH port
HOST="gcpapp29lhc"                   # Remote host (DNS or IP)
DB_NAME="gcppsg1"                    # Database name on remote
OUTPUT_DIR="outputs"                 # Local directory to save results
SSH_IDENTITY=""                      # Leave empty if ssh-agent handles it; set to /path/to/key if needed
FORCE_TTY=0                          # Set to 1 if sudo requires TTY

# Put your multi-line exclusions directly here (schema.table per line)
read -r -d '' EXCLUDE_LIST_RAW <<'EOF' || true
research.quote_snap
market_builder_2.volatility_surface
market_builder_2.bond_market_built_btt
market_data.snap
risk.riskbeta_reports
research.daily
_timescaledb_internal._compressed_hypertable_16
ticks.trade
research.quote_snap_credit
research.credit_vol
xccy.ubs_stir_analytics
EOF

# ----------------------------
# Prep: encode exclude list (safe single token)
# ----------------------------
# trim comments/blank lines first
CLEAN_EXCLUDE="$(printf '%s\n' "${EXCLUDE_LIST_RAW}" | grep -vE '^\s*($|#)' || true)"
EXCLUDE_B64="$(printf '%s' "${CLEAN_EXCLUDE}" | base64 -w0 2>/dev/null || printf '%s' "${CLEAN_EXCLUDE}" | base64)"  # macOS compat

mkdir -p "${OUTPUT_DIR}"
host_dir="${OUTPUT_DIR}/${HOST}"
mkdir -p "${host_dir}"

# ----------------------------
# SSH options (passwordless / public-key friendly)
# ----------------------------
SSH_OPTS=(
  -p "${SSH_PORT}"
  -o BatchMode=yes
  -o PreferredAuthentications=publickey
  -o PubkeyAuthentication=yes
  -o StrictHostKeyChecking=accept-new
  -o ControlMaster=auto
  -o ControlPersist=60s
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=4
)
if [[ -n "${SSH_IDENTITY}" ]]; then
  SSH_OPTS+=(-i "${SSH_IDENTITY}")
fi

SSH_TTY_FLAG=()
if [[ "${FORCE_TTY}" -eq 1 ]]; then
  SSH_TTY_FLAG=(-tt)
fi

# ----------------------------
# Remote worker script
#   Receives DB_NAME and EXCLUDE_B64 via env, decodes exclude list on remote
#   Uses '|' as psql field separator to avoid $'\t' pitfalls with set -u
# ----------------------------
REMOTE_SCRIPT='
set -euo pipefail

DB_NAME="${DB_NAME:-postgres}"
EXCLUDE_B64="${EXCLUDE_B64:-}"

TmpDir="/tmp"
TmpFile="$TmpDir/psql.$$.$RANDOM.out"

# Decode exclude list (may be empty)
EXCLUDE_LIST=""
if [[ -n "$EXCLUDE_B64" ]]; then
  # GNU and macOS base64 both support -d
  EXCLUDE_LIST="$(printf "%s" "$EXCLUDE_B64" | base64 -d || true)"
fi

# Build exclusion hash
declare -A SKIP=()
if [[ -n "$EXCLUDE_LIST" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # trim leading/trailing spaces
    key="$(echo "$line" | awk "{gsub(/^[ \t]+|[ \t]+$/, \"\"); print}")"
    [[ -z "$key" ]] && continue
    SKIP["$key"]=1
  done <<< "$EXCLUDE_LIST"
fi

# Get all non-system tables (schema|table)
psql -d "$DB_NAME" -At -F "|" -c "
  SELECT table_schema, table_name
  FROM information_schema.tables
  WHERE table_type = '\''BASE TABLE'\''
    AND table_schema NOT IN ( '\''pg_catalog'\'', '\''pg_toast'\'', '\''information_schema'\'', '\''pglogical'\'' )
  ORDER BY table_schema, table_name;
" > "$TmpFile"

# Determine max width for formatting
MaxLen=0
while IFS="|" read -r schema table; do
  [[ -z "${schema:-}" || -z "${table:-}" ]] && continue
  fqtn="$schema.$table"
  [[ -n "${SKIP[$fqtn]+x}" ]] && continue
  len=${#fqtn}
  (( len > MaxLen )) && MaxLen=$len
done < "$TmpFile"
((MaxLen++)) # spacing

echo
echo "Using Database -> $DB_NAME"
echo
echo "Counting table rows ..."
echo

RunTot=0
while IFS="|" read -r schema table; do
  [[ -z "${schema:-}" || -z "${table:-}" ]] && continue
  fqtn="$schema.$table"
  [[ -n "${SKIP[$fqtn]+x}" ]] && continue

  # quote identifiers safely
  qt="\"$schema\".\"$table\""

  printf "%-${MaxLen}.${MaxLen}s : " "$fqtn"

  result="$(psql -d "$DB_NAME" -AtqX -c "SELECT COUNT(*) FROM $qt;")" || {
    echo "ERROR counting $fqtn" >&2
    exit 1
  }

  # Trim whitespace
  result="$(echo "$result" | tr -d "[:space:]")"
  printf "%12d\n" "$result"
  (( RunTot += result ))
done < "$TmpFile"

# Separator line
LineLen=$((MaxLen + 3 + 12))
printf "%0.s=" $(seq 1 "$LineLen")
echo

printf "%-${MaxLen}.${MaxLen}s : %12d\n\n" "TOTAL ROWS" "$RunTot"

rm -f "$TmpFile"
'

echo "===> Connecting to host: ${HOST}"

# Run: we export DB_NAME and EXCLUDE_B64 *on the remote side* before invoking bash -s
if ! ssh "${SSH_TTY_FLAG[@]}" "${SSH_OPTS[@]}" "${SSH_USER}@${HOST}" \
  "sudo -u postgres bash -lc 'DB_NAME=\"${DB_NAME}\" EXCLUDE_B64=\"${EXCLUDE_B64}\" bash -s'" \
  <<< "${REMOTE_SCRIPT}" | tee "${host_dir}/counts.txt"
then
  echo "ERROR: Remote execution failed on ${HOST}" >&2
  exit 1
fi

echo "✅ Saved results to ${host_dir}/counts.txt"
