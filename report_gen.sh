#Source :

HOST="sadepollutp_gcp@10.6.66.14"; DB="gcppsg1"; shopt -s nullglob; mkdir -p "$HOST"; \
INCLUDE_SCHEMAS_RAW="$(ssh -o BatchMode=yes "$HOST" "sudo -u postgres -i psql -At -d \"$DB\" -c \"SELECT COALESCE(string_agg(quote_literal(nspname), ','), '') FROM pg_namespace WHERE nspname NOT IN ('pg_catalog','information_schema') AND nspname NOT LIKE 'pg_toast%%' AND nspname NOT LIKE 'pg_temp%%';\"")"; \
[ -z "$INCLUDE_SCHEMAS_RAW" ] && INCLUDE_SCHEMAS_RAW="'public'"; \
INCLUDE_SCHEMAS_ESCAPED="$(printf "%s" "$INCLUDE_SCHEMAS_RAW" | sed "s/'/''/g")"; \
for f in ./Validation_scripts/*.sql; do b="$(basename "$f" .sql)"; { \
  echo "=========== $b ==========="; \
  { printf "\\set include_schemas '%s'\n" "$INCLUDE_SCHEMAS_ESCAPED"; cat "$f"; } | \
  ssh -o BatchMode=yes "$HOST" "sudo -u postgres -i psql -v ON_ERROR_STOP=1 -d \"$DB\" -f -"; \
} > "$HOST/$b.log" 2>&1; done



#Target



HOST="sadepollutp_gcp@gcpapp29lhc"; DB="gcppsg1"; shopt -s nullglob; mkdir -p "$HOST"; \
INCLUDE_SCHEMAS_RAW="$(ssh -o BatchMode=yes "$HOST" "sudo -u postgres -i psql -At -d \"$DB\" -c \"SELECT COALESCE(string_agg(quote_literal(nspname), ','), '') FROM pg_namespace WHERE nspname NOT IN ('pg_catalog','information_schema') AND nspname NOT LIKE 'pg_toast%%' AND nspname NOT LIKE 'pg_temp%%';\"")"; \
[ -z "$INCLUDE_SCHEMAS_RAW" ] && INCLUDE_SCHEMAS_RAW="'public'"; \
INCLUDE_SCHEMAS_ESCAPED="$(printf "%s" "$INCLUDE_SCHEMAS_RAW" | sed "s/'/''/g")"; \
for f in ./Validation_scripts/*.sql; do b="$(basename "$f" .sql)"; { \
  echo "=========== $b ==========="; \
  { printf "\\set include_schemas '%s'\n" "$INCLUDE_SCHEMAS_ESCAPED"; cat "$f"; } | \
  ssh -o BatchMode=yes "$HOST" "sudo -u postgres -i psql -v ON_ERROR_STOP=1 -d \"$DB\" -f -"; \
} > "$HOST/$b.log" 2>&1; done




mkdir compare_output

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/checkconstraint.log sadepollutp_gcp\@10.6.66.14/checkconstraint.log > compare_output/checkconstraint.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/columnorder.log sadepollutp_gcp\@10.6.66.14/columnorder.log > compare_output/columnorder.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/dbsize.log sadepollutp_gcp\@10.6.66.14/dbsize.log > compare_output/dbsize.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/extension.log sadepollutp_gcp\@10.6.66.14/extension.log > compare_output/extension.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/fkeyconstraint.log sadepollutp_gcp\@10.6.66.14/fkeyconstraint.log > compare_output/fkeyconstraint.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/indexlist.log sadepollutp_gcp\@10.6.66.14/indexlist.log > compare_output/indexlist.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/invalid_cons.log sadepollutp_gcp\@10.6.66.14/invalid_cons.log > compare_output/invalid_cons.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/invalid_index.log sadepollutp_gcp\@10.6.66.14/invalid_index.log > compare_output/invalid_index.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/materialized_views.log sadepollutp_gcp\@10.6.66.14/materialized_views.log > compare_output/materialized_views.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/objectsummary.log sadepollutp_gcp\@10.6.66.14/objectsummary.log > compare_output/objectsummary.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/partitions.log sadepollutp_gcp\@10.6.66.14/partitions.log > compare_output/partitions.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/primarykey_constraint.log sadepollutp_gcp\@10.6.66.14/primarykey_constraint.log > compare_output/primarykey_constraint.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/schema.log sadepollutp_gcp\@10.6.66.14/schema.log > compare_output/schema.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/sequences.log sadepollutp_gcp\@10.6.66.14/sequences.log > compare_output/sequences.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/tables_list.log sadepollutp_gcp\@10.6.66.14/tables_list.log > compare_output/tables_list.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/triggers_list.log sadepollutp_gcp\@10.6.66.14/triggers_list.log > compare_output/triggers_list.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/udf_list.log sadepollutp_gcp\@10.6.66.14/udf_list.log > compare_output/udf_list.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/unique_constraints.log sadepollutp_gcp\@10.6.66.14/unique_constraints.log > compare_output/unique_constraints.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/users.log sadepollutp_gcp\@10.6.66.14/users.log > compare_output/users.log

grep -Fxv -f   sadepollutp_gcp@gcpapp29lhc/views.log sadepollutp_gcp\@10.6.66.14/views.log > compare_output/views.log

cd compare_output

for file in *.log; do echo "================$file=============="; cat "$file"; echo "======================END===================="; done >report.txt

grep -v timescale report.txt >report_final.txt

