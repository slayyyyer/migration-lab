#!/usr/bin/env bash
# Run every migration scenario against a real Postgres and publish a JSON report.
#
# For each scenario directory this script:
#   1. drops and recreates a scratch database (so every run starts from empty),
#   2. applies the shared baseline and the deterministic seed,
#   3. records a fingerprint of the data before the change,
#   4. runs a concurrent writer while Flyway applies each migration step,
#   5. runs the (optional) batched backfill,
#   6. re-checks the fingerprint and the scenario's assertions,
#   7. compares the worst writer latency against the scenario's budget.
#
# A scenario marked EXPECTED_FAIL=true passes only when it is actually caught.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PGURL="${PGURL:-postgresql://postgres:postgres@localhost:5432/postgres}"
# FLYWAY_BIN may name the launcher directly, or the file get-flyway.sh writes.
FLYWAY="${FLYWAY_BIN:-$root/.tools/flyway-bin}"
if [ -f "$FLYWAY" ]; then FLYWAY="$(cat "$FLYWAY")"; fi
PSQL="${PSQL_BIN:-psql}"
SCALE="${SCALE:-200000}"
OUT="${OUT:-dist/data/report.json}"
BATCH_SIZE="${BATCH_SIZE:-5000}"
CONTROL_DB="${CONTROL_DB:-lab_control}"
COMMIT="${GITHUB_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo local)}"

# postgresql://user:password@host:port/database
DB_USER="$(printf '%s' "$PGURL" | sed -E 's|^postgresql://([^:/@]+).*|\1|')"
DB_PASS="$(printf '%s' "$PGURL" | sed -E 's|^postgresql://[^:/@]+:([^@]*)@.*|\1|')"
DB_HOSTPORT="$(printf '%s' "$PGURL" | sed -E 's|^postgresql://[^@]*@([^/]+)/.*|\1|')"

mkdir -p "$(dirname "$OUT")" .work

log()  { printf '\n== %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; }

psql_db() { # psql_db <url> <args...>
  local url="$1"; shift
  "$PSQL" "$url" -v ON_ERROR_STOP=1 -q "$@"
}

jdbc_url() { printf 'jdbc:postgresql://%s/%s' "$DB_HOSTPORT" "$1"; }

run_backfill() {
  local batches=0 started finished updated
  started=$(date +%s%3N)
  while :; do
    updated="$(psql_db "$url" -t -A -v "batch=$BATCH_SIZE" -f "$dir/backfill.sql" 2>/dev/null | tail -1 | tr -d '[:space:]')"
    if [ -z "$updated" ] || [ "$updated" = "0" ]; then break; fi
    batches=$((batches + 1))
    if [ "$batches" -gt 400 ]; then
      notes="${notes}backfill hit the batch safety limit; "
      assertions_ok=0
      break
    fi
  done
  finished=$(date +%s%3N)
  steps_json="${steps_json}{\"name\":\"batched backfill ($batches transactions)\",\"ms\":$((finished - started))},"
  if [ "$batches" -eq 0 ]; then
    notes="${notes}backfill made no progress; "
    assertions_ok=0
  fi
}

reset_control() {
  psql_db "$PGURL" -c "drop database if exists \"$CONTROL_DB\" with (force)" >/dev/null 2>&1
  psql_db "$PGURL" -c "create database \"$CONTROL_DB\"" >/dev/null
  psql_db "${PGURL%/*}/$CONTROL_DB" -c "
    create table results (
      id            text primary key,
      title         text not null,
      status        text not null,
      expected_fail boolean not null,
      max_lock_ms   integer not null,
      lock_budget_ms integer not null,
      steps         jsonb not null,
      notes         text not null,
      run_at        timestamptz not null default now()
    )" >/dev/null
}

record_result() { # id title status expected_fail max_lock budget steps_json notes
  "${PSQL:-psql}" "${PGURL%/*}/$CONTROL_DB" -v ON_ERROR_STOP=1 -q \
    -v id="$1" -v title="$2" -v status="$3" -v expected="$4" \
    -v maxlock="$5" -v budget="$6" -v steps="$7" -v notes="$8" <<'SQL'
insert into results (id, title, status, expected_fail, max_lock_ms, lock_budget_ms, steps, notes)
values (:'id', :'title', :'status', :'expected'::boolean, :'maxlock'::integer,
        :'budget'::integer, :'steps'::jsonb, :'notes')
on conflict (id) do update set
  title = excluded.title, status = excluded.status, expected_fail = excluded.expected_fail,
  max_lock_ms = excluded.max_lock_ms, lock_budget_ms = excluded.lock_budget_ms,
  steps = excluded.steps, notes = excluded.notes, run_at = now();
SQL
}

reset_control

scenario_dirs=()
while IFS= read -r dir; do scenario_dirs+=("$dir"); done < <(
  find scenarios -mindepth 1 -maxdepth 1 -type d | sort
)

for dir in "${scenario_dirs[@]}"; do
  id="$(basename "$dir" | cut -d- -f1)"
  db="lab_migration_${id}"
  url="${PGURL%/*}/$db"

  # shellcheck disable=SC1090
  source "$dir/scenario.env"
  log "scenario $ID: $TITLE"

  psql_db "$PGURL" -c "drop database if exists \"$db\" with (force)" >/dev/null 2>&1
  psql_db "$PGURL" -c "create database \"$db\"" >/dev/null || { fail "could not create $db"; continue; }

  steps_json="["
  notes=""
  assertions_ok=1

  if ! psql_db "$url" -f shared/baseline.sql >.work/baseline.log 2>&1; then
    fail "baseline failed for $ID"; tail -20 .work/baseline.log
    record_result "$id" "$TITLE" "error" "$EXPECTED_FAIL" 0 "$LOCK_BUDGET_MS" "[]" "baseline failed"
    continue
  fi

  if ! psql_db "$url" -v "scale=$SCALE" -f shared/seed.sql >.work/seed.log 2>&1; then
    fail "seed failed for $ID"; tail -20 .work/seed.log
    record_result "$id" "$TITLE" "error" "$EXPECTED_FAIL" 0 "$LOCK_BUDGET_MS" "[]" "seed failed"
    continue
  fi

  # Fingerprint before the change. checks.sql is mode-aware: before stores, after compares.
  if ! psql_db "$url" -v mode=before -f "$dir/checks.sql" >.work/checks-before.log 2>&1; then
    fail "pre-check failed for $ID"; tail -20 .work/checks-before.log
    assertions_ok=0
    notes="${notes}pre-check failed; "
  fi

  # Concurrent writer: latency is the user-visible measure of lock contention.
  latency_file=".work/latency-$ID.txt"
  : >"$latency_file"
  probe_flag=".work/probe-$ID.flag"
  : >"$probe_flag"
  (
    while [ -f "$probe_flag" ]; do
      started=$(date +%s%3N)
      "$PSQL" "$url" -q -c "set lock_timeout='5s'; update orders set updated_at = now() where id = (select id from orders limit 1)" >/dev/null 2>&1
      finished=$(date +%s%3N)
      printf '%s\n' "$((finished - started))" >>"$latency_file"
      sleep 0.05
    done
  ) &
  probe_pid=$!

  migration_targets="$(find "$dir/migrations" -maxdepth 1 -name 'V*.sql' 2>/dev/null | wc -l)"
  lockfile="$(mktemp)"
  backcompat_done=0

  for target in $(seq 1 "$migration_targets"); do
    started=$(date +%s%3N)
    if "$FLYWAY" -url="$(jdbc_url "$db")" -user="$DB_USER" -password="$DB_PASS" \
        -locations="filesystem:$dir/migrations" -baselineOnMigrate=true -baselineVersion=0 \
        -table=flyway_schema_history -target="$target" -connectRetries=5 migrate \
        >".work/flyway-$ID-$target.log" 2>&1; then
      finished=$(date +%s%3N)
      step_name="$(basename "$(ls "$dir/migrations"/V${target}__*.sql 2>/dev/null | head -1)" .sql)"
      steps_json="${steps_json}{\"name\":\"$step_name\",\"ms\":$((finished - started))},"
    else
      finished=$(date +%s%3N)
      steps_json="${steps_json}{\"name\":\"V${target} (failed)\",\"ms\":$((finished - started))},"
      notes="${notes}V${target} failed: $(tail -3 ".work/flyway-$ID-$target.log" | tr '\n' ' ' | tr -d "'" | tr -s ' ' | cut -c1-160); "
      assertions_ok=0
      break
    fi

    # Prove the previous release's query still works while the schema is mid-expand.
    if [ "${BACKCOMPAT_AFTER_TARGET:-0}" = "$target" ] && [ -f "$dir/previous-queries.sql" ]; then
      if psql_db "$url" -f "$dir/previous-queries.sql" >.work/backcompat-$ID.log 2>&1; then
        steps_json="${steps_json}{\"name\":\"previous release query set\",\"ms\":0},"
      else
        steps_json="${steps_json}{\"name\":\"previous release query set (broken)\",\"ms\":0},"
        notes="${notes}backward compatibility broke after V${target}; "
        assertions_ok=0
      fi
      backcompat_done=1
    fi

    # The backfill has to happen between expand and contract: after the new column exists
    # and before the old one is dropped. Running it at the end would be too late.
    if [ "${BACKFILL_AFTER_TARGET:-0}" = "$target" ] && [ -f "$dir/backfill.sql" ]; then
      run_backfill
    fi
  done

  # Some statements cannot run inside a transaction at all (CREATE INDEX CONCURRENTLY),
  # so they are executed here rather than through Flyway. That limitation is itself one
  # of the things scenario 05 demonstrates.
  if [ -n "${EXTRA_STEP:-}" ] && [ -f "$dir/$EXTRA_STEP" ]; then
    started=$(date +%s%3N)
    if psql_db "$url" -f "$dir/$EXTRA_STEP" >.work/extra-$ID.log 2>&1; then
      finished=$(date +%s%3N)
      steps_json="${steps_json}{\"name\":\"$(basename "$EXTRA_STEP" .sql)\",\"ms\":$((finished - started))},"
    else
      finished=$(date +%s%3N)
      steps_json="${steps_json}{\"name\":\"$(basename "$EXTRA_STEP" .sql) (failed)\",\"ms\":$((finished - started))},"
      notes="${notes}extra step failed; "
      assertions_ok=0
    fi
  fi

  # Scenarios that do not pin a target run the backfill after every migration.
  if [ -z "${BACKFILL_AFTER_TARGET:-}" ] && [ -f "$dir/backfill.sql" ]; then
    run_backfill
  fi

  rm -f "$probe_flag"
  wait "$probe_pid" 2>/dev/null
  max_lock="$(sort -n "$latency_file" 2>/dev/null | tail -1)"
  max_lock="${max_lock:-0}"

  if ! psql_db "$url" -v mode=after -f "$dir/checks.sql" >.work/checks-after.log 2>&1; then
    assertion_message="$(grep -oE 'ERROR:  .*' .work/checks-after.log | head -1 | sed 's/ERROR:  //' | tr -d "'" | cut -c1-160)"
    notes="${notes}${assertion_message:-assertions failed}; "
    assertions_ok=0
  fi

  steps_json="${steps_json%,}]"

  lock_ok=1
  if [ "$max_lock" -gt "$LOCK_BUDGET_MS" ]; then lock_ok=0; fi

  status="pass"
  if [ "$EXPECTED_FAIL" = "true" ]; then
    # The scenario passes only when the harness actually catches the bad migration.
    if [ "$assertions_ok" = "1" ] && [ "$lock_ok" = "1" ]; then
      status="not-caught"
      notes="${notes}expected the harness to catch this migration, but it passed; "
    else
      status="caught"
      [ "$lock_ok" = "0" ] && notes="${notes}writer blocked ${max_lock}ms (budget ${LOCK_BUDGET_MS}ms); "
    fi
  else
    if [ "$assertions_ok" = "0" ] || [ "$lock_ok" = "0" ]; then
      status="fail"
      [ "$lock_ok" = "0" ] && notes="${notes}writer blocked ${max_lock}ms (budget ${LOCK_BUDGET_MS}ms); "
    fi
    if [ "$backcompat_done" = "0" ] && [ -f "$dir/previous-queries.sql" ]; then
      notes="${notes}backward-compat probe never ran; "
    fi
  fi

  if [ "$status" != "pass" ] && [ "$status" != "caught" ]; then
    printf '::error::scenario %s (%s): %s\n' "$ID" "$status" "${notes:-no detail}"
  fi

  printf '   %s (%s ms max writer latency, budget %s ms)\n' "$status" "$max_lock" "$LOCK_BUDGET_MS"
  record_result "$id" "$TITLE" "$status" "$EXPECTED_FAIL" "$max_lock" "$LOCK_BUDGET_MS" "$steps_json" "${notes:-none}"
done

# The report is generated by Postgres, so there is no JSON assembly in bash and no
# escaping bugs to argue with.
"${PSQL}" "${PGURL%/*}/$CONTROL_DB" -t -A -v ON_ERROR_STOP=1 -v commit="$COMMIT" -v scale="$SCALE" <<'SQL' >"$OUT"
select json_build_object(
  'generatedAt', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'commit', :'commit',
  'seedOrders', :'scale'::integer,
  'postgres', current_setting('server_version'),
  'scenarios', coalesce((
     select json_agg(json_build_object(
       'id', id,
       'title', title,
       'status', status,
       'expectedFail', expected_fail,
       'maxLockMs', max_lock_ms,
       'lockBudgetMs', lock_budget_ms,
       'steps', steps,
       'notes', notes,
       'runAt', to_char(run_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
     ) order by id)
     from results), '[]'::json)
)::text;
SQL

echo
echo "report written to $OUT"
jq -r '.scenarios[] | "\(.id)  \(.status)\t\(.title)"' "$OUT" 2>/dev/null || head -c 400 "$OUT"

if grep -q '"status": "fail"' "$OUT" 2>/dev/null || grep -q '"status": "not-caught"' "$OUT" 2>/dev/null; then
  echo "one or more scenarios failed" >&2
  exit 1
fi
