#!/usr/bin/env bash
# =====================================================================
# Portfolio 5 (part B): PostgreSQL streaming replication on ONE machine.
# A second server (the replica) continuously copies the primary's changes.
#
#   ./02_replication_postgres.sh          build the replica and show the evidence
#   ./02_replication_postgres.sh promote  simulate failover: promote the replica
#   ./02_replication_postgres.sh cleanup  stop and delete the replica
#
# Needs: Linux, macOS or WSL; PostgreSQL client + server binaries on PATH
#        (pg_basebackup, pg_ctl, psql, pg_isready); run as the OS user that is
#        allowed to start PostgreSQL. Your primary must allow a replication
#        connection (the default pg_hba.conf entry for 'replication' on
#        localhost works with a superuser or a REPLICATION role).
# Settings (override with environment variables):
#   PGHOST (default localhost)  PGUSER (default postgres)  PGPASSWORD if needed
#   PRIMARY_PORT (default 5432) REPLICA_PORT (default 5434)
#   REPLICA_DIR  (default $HOME/citylib_replica)   DB (default citylib)
# =====================================================================
set -euo pipefail
export PGHOST="${PGHOST:-localhost}"
export PGUSER="${PGUSER:-postgres}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"
REPLICA_PORT="${REPLICA_PORT:-5434}"
REPLICA_DIR="${REPLICA_DIR:-$HOME/citylib_replica}"
DB="${DB:-citylib}"
P="psql -X -q -d $DB -p $PRIMARY_PORT"
R="psql -X -q -d $DB -p $REPLICA_PORT"
step() { printf '\n######## %s\n' "$1"; }

case "${1:-build}" in
cleanup)
  pg_ctl -D "$REPLICA_DIR" -m fast stop 2>/dev/null || true
  rm -rf "$REPLICA_DIR"; echo "Replica removed."; exit 0 ;;
promote)
  step "FAILOVER: promote the replica to a standalone primary"
  pg_ctl -D "$REPLICA_DIR" promote -w
  $R -c "SELECT pg_is_in_recovery() AS still_a_replica;"
  step "The promoted server now ACCEPTS WRITES"
  $R -c "INSERT INTO replication_check (note) VALUES ('written after failover to the promoted replica') RETURNING id, note;"
  echo "(The old primary is now out of sync with this server. Run './02_replication_postgres.sh cleanup' when done.)"
  exit 0 ;;
build) ;;
*) echo "Unknown command"; exit 1 ;;
esac

step "1. Create a table on the PRIMARY to track replication"
$P -c "CREATE TABLE IF NOT EXISTS replication_check (id SERIAL PRIMARY KEY, note TEXT, at TIMESTAMPTZ DEFAULT now());"

step "2. Take a base backup of the primary (this seeds the replica; -R writes the replication settings)"
rm -rf "$REPLICA_DIR"
pg_basebackup -h "$PGHOST" -p "$PRIMARY_PORT" -D "$REPLICA_DIR" -R -X stream --checkpoint=fast
chmod 700 "$REPLICA_DIR"

step "3. Start the REPLICA on port $REPLICA_PORT"
pg_ctl -D "$REPLICA_DIR" -o "-p $REPLICA_PORT ${REPLICA_EXTRA_OPTS:-}" -l "$REPLICA_DIR/replica.log" -w start
for i in $(seq 1 20); do pg_isready -q -p "$REPLICA_PORT" && break; sleep 1; done

step "4. Evidence: the replica reports that it is in recovery (a standby)"
$R -c "SELECT pg_is_in_recovery() AS is_replica;"

step "5. Evidence: the PRIMARY sees a connected streaming replica"
$P -x -c "SELECT client_addr, state, sent_lsn, replay_lsn, sync_state FROM pg_stat_replication;"

step "6. Write on the PRIMARY, read from the REPLICA"
$P -c "INSERT INTO replication_check (note) VALUES ('written on the primary');"
sleep 1
$R -c "SELECT id, note FROM replication_check ORDER BY id DESC LIMIT 3;"

step "7. A write on the REPLICA is refused (it is read-only)"
$R -c "INSERT INTO replication_check (note) VALUES ('should fail');" || echo "^ expected error: replicas are read-only"

step "8. Replication lag (bytes behind the primary)"
$P -c "SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes FROM pg_stat_replication;"

echo
echo "Done. Next: './02_replication_postgres.sh promote' to simulate failover, then 'cleanup'."
