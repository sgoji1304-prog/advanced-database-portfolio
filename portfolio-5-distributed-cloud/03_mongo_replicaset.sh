#!/usr/bin/env bash
# =====================================================================
# Portfolio 5 (part C): a 3-member MongoDB replica set on one machine.
# Shows replication, read-only secondaries, and automatic failover (election).
#
#   ./03_mongo_replicaset.sh            build the replica set and show evidence
#   ./03_mongo_replicaset.sh failover   force the primary to step down, watch the election
#   ./03_mongo_replicaset.sh cleanup    shut everything down and delete the data
#
# Needs: Linux, macOS or WSL (uses mongod --fork); mongod and mongosh on PATH.
# Uses ports 27018-27020, so it does not touch a MongoDB already running on 27017.
# Settings: MONGO_RS_DIR (default $HOME/citylib_rs)
# =====================================================================
set -euo pipefail
BASE="${MONGO_RS_DIR:-$HOME/citylib_rs}"
PORTS=(27018 27019 27020)
RS=citylibRS
step() { printf '\n######## %s\n' "$1"; }
q() { mongosh --quiet --port "$1" --eval "$2"; }          # run JS against one member

primary_port() {                                            # ask any member who the primary is
  q 27018 'print(rs.hello().primary.split(":")[1])' 2>/dev/null || q 27019 'print(rs.hello().primary.split(":")[1])'
}
status() { q "$1" 'rs.status().members.forEach(m => print(m.name.padEnd(18), m.stateStr))'; }

case "${1:-build}" in
cleanup)
  for p in "${PORTS[@]}"; do
    mongosh --quiet --port "$p" --eval 'db.getSiblingDB("admin").shutdownServer({force:true})' >/dev/null 2>&1 || true
  done
  sleep 2; rm -rf "$BASE"; echo "Replica set removed."; exit 0 ;;
failover)
  step "Members BEFORE failover"; status "$(primary_port)"
  OLD=$(primary_port); echo "Current primary is on port $OLD; asking it to step down..."
  q "$OLD" 'try { rs.stepDown(30) } catch (e) { print("(connection dropped during stepDown, as expected)") }' || true
  sleep 12
  NEW=$(primary_port)
  step "Members AFTER failover (a different member is now PRIMARY)"; status "$NEW"
  step "Writes keep working on the NEW primary (port $NEW)"
  q "$NEW" 'db.getSiblingDB("citylib_nosql").rs_check.insertOne({note:"written after failover", at:new Date()}); print("insert OK")'
  exit 0 ;;
build) ;;
*) echo "Unknown command"; exit 1 ;;
esac

step "1. Start three mongod processes, all in replica set '$RS'"
rm -rf "$BASE"; mkdir -p "$BASE"/n1 "$BASE"/n2 "$BASE"/n3
for i in 0 1 2; do
    nohup mongod --replSet "$RS" --port "${PORTS[$i]}" --dbpath "$BASE/n$((i+1))" \
         --bind_ip localhost --logpath "$BASE/n$((i+1)).log" >/dev/null 2>&1 &
done
sleep 3

step "2. Initiate the replica set"
q 27018 'rs.initiate({_id:"'$RS'", members:[
  {_id:0, host:"localhost:27018"}, {_id:1, host:"localhost:27019"}, {_id:2, host:"localhost:27020"}]}).ok'
for i in $(seq 1 30); do
  [ "$(q 27018 'print(rs.hello().isWritablePrimary)' 2>/dev/null || true)" = "true" ] && break; sleep 1
done
sleep 3

step "3. Evidence: one PRIMARY and two SECONDARY members"
status 27018

step "4. Write on the PRIMARY"
P=$(primary_port)
q "$P" 'db.getSiblingDB("citylib_nosql").rs_check.insertOne({note:"written on the primary", at:new Date()}); print("insert OK")'
sleep 2

step "5. Read the same document from a SECONDARY (replicated)"
SEC=27019; [ "$P" = "27019" ] && SEC=27020
q "$SEC" 'db.getMongo().setReadPref("secondaryPreferred"); printjson(db.getSiblingDB("citylib_nosql").rs_check.find({}, {_id:0, note:1}).toArray())'

step "6. A write sent to a SECONDARY is refused"
q "$SEC" 'try { db.getSiblingDB("citylib_nosql").rs_check.insertOne({note:"should fail"}) } catch (e) { print("expected error: " + e.codeName) }'

echo; echo "Done. Next: './03_mongo_replicaset.sh failover', then 'cleanup'."
