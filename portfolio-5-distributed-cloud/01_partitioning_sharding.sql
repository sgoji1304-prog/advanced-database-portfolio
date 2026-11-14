-- =====================================================================
-- Portfolio 5 (part A): horizontal partitioning and shard-key design
-- Case study: CityLib. Uses the `loans` data from Portfolio 1.
--
--   RANGE partitions by loan_date : time-based data (archive old quarters)
--   HASH  partitions by member_id : the same idea as SHARDING. On one server
--     these are 4 tables; in a real distributed deployment each one would
--     live on a DIFFERENT server (for example with Citus or postgres_fdw).
-- Run with:  psql -d citylib -f 01_partitioning_sharding.sql
-- =====================================================================
\pset border 2

-- ---------------------------------------------------------------------
-- A. RANGE partitioning by quarter
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS loans_by_date CASCADE;
CREATE TABLE loans_by_date (
    loan_id      INT  NOT NULL,
    copy_id      INT  NOT NULL,
    member_id    INT  NOT NULL,
    staff_id     INT  NOT NULL,
    loan_date    DATE NOT NULL,
    due_date     DATE NOT NULL,
    return_date  DATE,
    PRIMARY KEY (loan_id, loan_date)          -- a PK on a partitioned table must include the partition key
) PARTITION BY RANGE (loan_date);

DO $$
DECLARE d DATE;
BEGIN
  FOR d IN SELECT g::date
           FROM generate_series(date_trunc('quarter', CURRENT_DATE - 900)::date,
                                date_trunc('quarter', CURRENT_DATE + 90)::date,
                                interval '3 months') g
  LOOP
    EXECUTE format('CREATE TABLE %I PARTITION OF loans_by_date FOR VALUES FROM (%L) TO (%L)',
                   'loans_' || to_char(d, 'YYYY') || '_q' || to_char(d, 'Q'),
                   d, (d + interval '3 months')::date);
  END LOOP;
END $$;
CREATE TABLE loans_default PARTITION OF loans_by_date DEFAULT;   -- catches anything outside the ranges

INSERT INTO loans_by_date
SELECT loan_id, copy_id, member_id, staff_id, loan_date, due_date, return_date FROM loans;
CREATE INDEX idx_lbd_member ON loans_by_date (member_id);
ANALYZE loans_by_date;

\echo
\echo '#### A1. Rows per range partition'
SELECT tableoid::regclass AS partition, count(*) AS rows
FROM loans_by_date GROUP BY 1 ORDER BY 1;

\echo
\echo '#### A2. PARTITION PRUNING: filtering on the partition key touches only the needed partitions'
EXPLAIN (COSTS OFF)
SELECT count(*) FROM loans_by_date
WHERE loan_date BETWEEN CURRENT_DATE - 100 AND CURRENT_DATE - 70;

\echo
\echo '#### A3. No pruning when the filter is NOT on the partition key (every partition is searched)'
EXPLAIN (COSTS OFF)
SELECT count(*) FROM loans_by_date WHERE member_id = 1234;

-- ---------------------------------------------------------------------
-- B. HASH partitioning by member_id  (the sharding pattern)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS loans_sharded CASCADE;
CREATE TABLE loans_sharded (
    loan_id      INT  NOT NULL,
    copy_id      INT  NOT NULL,
    member_id    INT  NOT NULL,
    staff_id     INT  NOT NULL,
    loan_date    DATE NOT NULL,
    due_date     DATE NOT NULL,
    return_date  DATE,
    PRIMARY KEY (loan_id, member_id)          -- shard key included
) PARTITION BY HASH (member_id);

CREATE TABLE loans_shard_0 PARTITION OF loans_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE loans_shard_1 PARTITION OF loans_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE loans_shard_2 PARTITION OF loans_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE loans_shard_3 PARTITION OF loans_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 3);

INSERT INTO loans_sharded
SELECT loan_id, copy_id, member_id, staff_id, loan_date, due_date, return_date FROM loans;
ANALYZE loans_sharded;

\echo
\echo '#### B1. Data distribution across the 4 shards (a good shard key spreads rows evenly)'
SELECT tableoid::regclass AS shard, count(*) AS rows,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM loans_sharded GROUP BY 1 ORDER BY 1;

\echo
\echo '#### B2. TARGETED query: filter on the shard key reads exactly ONE shard'
EXPLAIN (COSTS OFF) SELECT * FROM loans_sharded WHERE member_id = 1234;

\echo
\echo '#### B3. SCATTER-GATHER query: no shard key in the filter, so ALL shards must be asked'
EXPLAIN (COSTS OFF) SELECT count(*) FROM loans_sharded WHERE loan_date = CURRENT_DATE - 100;

\echo
\echo '#### B4. Which shard holds which member? (the routing rule)'
SELECT member_id, tableoid::regclass AS shard
FROM loans_sharded WHERE member_id IN (1, 2, 3, 4, 5, 6) GROUP BY 1, 2 ORDER BY 1;
