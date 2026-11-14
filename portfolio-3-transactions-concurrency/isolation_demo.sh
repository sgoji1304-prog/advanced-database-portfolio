#!/usr/bin/env bash
# =====================================================================
# Isolation-level demo: a NON-REPEATABLE READ.
# Session A reads the status of copy 700 twice inside one transaction.
# Between the two reads, session B damages the copy and commits.
#
# Usage:  ./isolation_demo.sh read_committed     # A sees two different values
#         ./isolation_demo.sh repeatable_read    # A sees the same value twice
# =====================================================================
LEVEL="${1:-read_committed}"
case "$LEVEL" in
  read_committed)  ISO="ISOLATION LEVEL READ COMMITTED"  ;;
  repeatable_read) ISO="ISOLATION LEVEL REPEATABLE READ" ;;
  *) echo "Unknown level: $LEVEL"; exit 1 ;;
esac
PSQL="psql -X -q -d ${DB:-citylib}"

$PSQL -c "UPDATE book_copies SET status = 'available' WHERE copy_id = 700;" >/dev/null
echo "=== Isolation level for session A: $LEVEL ==="

$PSQL 2>&1 <<SQL | sed 's/^/[A] /' &
BEGIN $ISO;
SELECT 'first read : copy 700 is ' || status AS result FROM book_copies WHERE copy_id = 700;
SELECT pg_sleep(2) \g /dev/null
SELECT 'second read: copy 700 is ' || status AS result FROM book_copies WHERE copy_id = 700;
COMMIT;
SQL

$PSQL 2>&1 <<SQL | sed 's/^/[B] /' &
SELECT pg_sleep(1) \g /dev/null
UPDATE book_copies SET status = 'damaged' WHERE copy_id = 700;
SELECT 'damaged copy 700 and committed (autocommit)' AS step;
SQL

wait
$PSQL -c "UPDATE book_copies SET status = 'available' WHERE copy_id = 700;" >/dev/null
echo "(copy 700 reset to available)"
