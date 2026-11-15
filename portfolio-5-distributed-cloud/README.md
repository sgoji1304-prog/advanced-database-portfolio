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

## 3. Expected results

| Exercise 
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



## 4. Technical Reflection 
Replication copies the same data to several servers, while sharding splits different data across servers. I demonstrated replication with PostgreSQL streaming replication and a MongoDB replica set, and sharding with the four loans_shard tables in PostgreSQL. The partitioning results showed me that the partition key matters: a filter on the partition key (loan_date) let PostgreSQL scan only the one partition it needed and remove the rest, while a filter on member_id had to scan every partition. I used member_id as the shard key because loans are usually searched by the member who borrowed them, so those queries read just one shard. A query without the shard key, such as a filter on loan_date, is scatter-gather and must check all four shards, which adds work and response time. The even spread (about 24% to 26% per shard) matters because it stops one shard from carrying too much of the workload. Zero replication lag showed that the replica was fully caught up at the time of testing, and the refused INSERT showed that a replica is read-only. On a busy system lag can grow when the primary produces changes faster than the replica can receive and apply them. In PostgreSQL I promoted the replica by hand, while the MongoDB replica set elected a new primary automatically after the old one stepped down, and a majority of members is required so that two members cannot both become primary (split-brain). Because the replication was asynchronous, recent commits might not have reached the replica before a crash and could be lost during failover. Synchronous replication reduces that risk by making the primary wait for the replica, but it adds delay to each transaction. I could demonstrate partitioning, sharding, PostgreSQL replication and failover, and the MongoDB replica set on my own machine. The cloud deployment in ARCHITECTURE.md was only discussed as a proposed design and not deployed. On Windows, the MongoDB script needed a small edit, replacing --fork with nohup ... &, to run.
