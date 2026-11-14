#!/usr/bin/env bash
# =====================================================================
# Deadlock demo: two sessions lock the same two copies in OPPOSITE order.
#   A locks copy 701 then wants 702.   B locks copy 702 then wants 701.
# PostgreSQL detects the cycle (after deadlock_timeout, 1s by default),
# aborts ONE session with "deadlock detected", and the other completes.
# Prevention: always lock rows in a consistent order (e.g. ascending copy_id).
# =====================================================================
PSQL="psql -X -q -d ${DB:-citylib}"
echo "=== Deadlock demo ==="

$PSQL 2>&1 <<'SQL' | sed 's/^/[A] /' &
BEGIN;
UPDATE book_copies SET status = 'available' WHERE copy_id = 701;
SELECT 'locked copy 701' AS step;
SELECT pg_sleep(1) \g /dev/null
UPDATE book_copies SET status = 'available' WHERE copy_id = 702;
SELECT 'locked copy 702 too' AS step;
COMMIT;
SQL

$PSQL 2>&1 <<'SQL' | sed 's/^/[B] /' &
SELECT pg_sleep(0.3) \g /dev/null
BEGIN;
UPDATE book_copies SET status = 'available' WHERE copy_id = 702;
SELECT 'locked copy 702' AS step;
SELECT pg_sleep(1) \g /dev/null
UPDATE book_copies SET status = 'available' WHERE copy_id = 701;
SELECT 'locked copy 701 too' AS step;
COMMIT;
SQL

wait
echo "=== One session was killed by PostgreSQL's deadlock detector; the other committed. ==="
