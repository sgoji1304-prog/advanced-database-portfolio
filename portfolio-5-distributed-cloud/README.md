# Portfolio 5: Distributed and Cloud Database Exercise

Case study: **CityLib Public Library**, scaled to a regional network of branches. This portfolio has one design document and three hands-on exercises.

## 1. Files

| File | Type | Covers |
|---|---|---|
| `ARCHITECTURE.md` | Design discussion | Replication, sharding, CAP/consistency, availability, disaster recovery, cloud deployment options |
| `01_partitioning_sharding.sql` | Hands-on (SQL only) | Range partitioning and pruning, hash "sharding" by `member_id`, targeted vs scatter-gather queries |
| `02_replication_postgres.sh` | Hands-on | PostgreSQL streaming replication, read-only replica, lag, failover by promotion |
| `03_mongo_replicaset.sh` | Hands-on | 3-member MongoDB replica set, replication, secondaries refusing writes, automatic election |

## 2. How to run

```bash
# A. Partitioning / sharding (works on any OS, needs only psql)
psql -d citylib -f 01_partitioning_sharding.sql

# B. PostgreSQL replication (Linux, macOS or WSL)
chmod +x *.sh
PGUSER=postgres ./02_replication_postgres.sh            # builds the replica and prints the evidence
./02_replication_postgres.sh promote                    # failover
./02_replication_postgres.sh cleanup                    # remove the replica

# C. MongoDB replica set (Linux, macOS or WSL)
./03_mongo_replicaset.sh
./03_mongo_replicaset.sh failover
./03_mongo_replicaset.sh cleanup
```

Settings you may need to change are listed at the top of each script (`PGHOST`, `PGUSER`, `PGPASSWORD`, `PRIMARY_PORT`, `REPLICA_PORT`, `DB`). The replica needs a PostgreSQL role that may take a base backup, and the default superuser works. Take **screenshots of each step's output** and save them in `screenshots/`.

If you are on **Windows without WSL**, parts B and C cannot run as written. Do part A, which works everywhere, and cover replication through `ARCHITECTURE.md`, stating that clearly in your documentation.

## 3. Expected results

| Exercise | What you should see |
|---|---|
| A1 | Loans spread across about 9 quarterly partitions |
| A2 | `Subplans Removed: 12`: only the one partition matching the date range is scanned (**partition pruning**) |
| A3 | A filter on `member_id` (not the partition key) scans every partition |
| B1 | The four hash shards each hold about 25% of the loans |
| B2 | `WHERE member_id = 1234` reads exactly **one** shard (targeted query) |
| B3 | A filter on `loan_date` reads **all** shards (scatter-gather) |
| Replication 4 | `is_replica = t` on the standby |
| Replication 5 | `pg_stat_replication` shows `state = streaming` |
| Replication 6 | A row written on the primary appears on the replica |
| Replication 7 | `ERROR: cannot execute INSERT in a read-only transaction` on the replica |
| Replication 8 | `lag_bytes` at or near 0 |
| Promote | `still_a_replica = f` and writes now succeed |
| Mongo 3 | One `PRIMARY` and two `SECONDARY` members |
| Mongo 5-6 | Document visible on the secondary, write to the secondary refused |
| Mongo failover | A different member becomes `PRIMARY` and writes continue |

## 4. Key concepts to explain in your own words

- **Replication vs sharding:** replication copies the *same* data to several servers (availability, read scaling), while sharding splits *different* data across servers (write and storage scaling). Production systems use both.
- **Shard key choice:** it decides which queries are cheap (targeted) and which are expensive (scatter-gather). Explain why `member_id` was used for loans.
- **Consistency vs availability:** loans need strong consistency, while reports and the catalogue can tolerate stale reads (`ARCHITECTURE.md`, section 4).
- **Asynchronous replication risk:** a primary crash can lose the last commits that had not yet reached the replica, and synchronous replication removes that risk at a latency cost.
- **Failover:** a replica is promoted (PostgreSQL) or elected (MongoDB). Mention split-brain and why a majority is needed.

## 5. Technical Reflection (draft, rewrite in your own words)

*Add 3-5 sentences on what the scatter-gather query taught you about shard keys, what you observed about replication lag, and which parts of the design you could demonstrate locally versus only discuss (the cloud deployment).*
