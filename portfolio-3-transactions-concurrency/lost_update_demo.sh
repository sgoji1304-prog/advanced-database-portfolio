#!/usr/bin/env bash
# =====================================================================
# Lost-update demo: two staff members edit the SAME fine at the same time.
#   Staff A waives 100 (fine should go 500 -> 400)
#   Staff B adds a 50 surcharge  (fine should go 400 -> 450 overall)
# The correct final amount is 450.
#
# Usage:  ./lost_update_demo.sh unsafe            # shows the bug  (final 550)
#         ./lost_update_demo.sh for_update        # fix 1: row lock (final 450)
#         ./lost_update_demo.sh atomic            # fix 2: relative UPDATE (final 450)
#         ./lost_update_demo.sh repeatable_read   # fix 3: isolation level (B gets an error, final 400)
# Connection settings come from the usual PGHOST/PGPORT/PGUSER/PGPASSWORD
# variables. Database name: DB (default citylib).
# =====================================================================
MODE="${1:-unsafe}"
PSQL="psql -X -q -d ${DB:-citylib}"

case "$MODE" in
  unsafe)          ISO="";                                LK="";           EA=':a - 100';     EB=':a + 50'     ;;
  for_update)      ISO="";                                LK="FOR UPDATE"; EA=':a - 100';     EB=':a + 50'     ;;
  atomic)          ISO="";                                LK="";           EA='amount - 100'; EB='amount + 50' ;;
  repeatable_read) ISO="ISOLATION LEVEL REPEATABLE READ"; LK="";           EA=':a - 100';     EB=':a + 50'     ;;
  *) echo "Unknown mode: $MODE"; exit 1 ;;
esac

$PSQL -c "UPDATE fines SET amount = 500 WHERE fine_id = 1;" >/dev/null
echo "=== MODE: $MODE | fine #1 starts at 500 | correct final answer = 450 ==="

# ---- Session A: reads at t=0, writes at t=2 ----
$PSQL 2>&1 <<SQL | sed 's/^/[A] /' &
BEGIN $ISO;
SELECT amount AS a FROM fines WHERE fine_id = 1 $LK \gset
SELECT 'read amount = ' || :a AS step;
SELECT pg_sleep(2) \g /dev/null
UPDATE fines SET amount = $EA WHERE fine_id = 1;
COMMIT;
SELECT 'waived 100 and committed' AS step;
SQL

# ---- Session B: starts at t=0.5, writes at t=3.5 ----
$PSQL 2>&1 <<SQL | sed 's/^/[B] /' &
SELECT pg_sleep(0.5) \g /dev/null
BEGIN $ISO;
SELECT amount AS a FROM fines WHERE fine_id = 1 $LK \gset
SELECT 'read amount = ' || :a AS step;
SELECT pg_sleep(3) \g /dev/null
UPDATE fines SET amount = $EB WHERE fine_id = 1;
COMMIT;
SELECT 'session finished' AS step;
SQL

wait
echo "=== FINAL amount of fine #1 ==="
$PSQL -c "SELECT fine_id, amount FROM fines WHERE fine_id = 1;"
