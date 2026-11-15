# Portfolio 2: Query Processing and Optimisation

Case study: **CityLib Public Library** (see Portfolio 1). Database: PostgreSQL, about 200,000 loans, 80,000 fines, 6,000 copies, 5,000 members.

## 1. Files

| File | Purpose |
|---|---|
| `queries.sql` | The five business queries (Q1-Q5) |
| `explain.sql` | `EXPLAIN (ANALYZE, BUFFERS)` for each query |
| `indexes.sql` | Indexes and a materialised view chosen from the "before" plans |
| `reset_indexes.sql` | Removes them so the experiment can be repeated |
| `results/` | **Your** saved plan outputs and screenshots (create this folder) |

## 2. How to reproduce

```bash
mkdir -p results
psql -d citylib -f explain.sql > results/plans_before.txt     # baseline
psql -d citylib -f indexes.sql                                 # optimise
psql -d citylib -f explain.sql > results/plans_after.txt      # re-measure
```



## 3. The queries

| # | Business question | Why it matters |
|---|---|---|
| Q1 | Loan history of one member | Front-desk lookup, runs constantly |
| Q2 | Overdue unreturned loans with member contact | Daily reminder emails |
| Q3 | Ten most borrowed books | Management report, scans everything |
| Q4 | Fines per day for one week | Finance report, a date range |
| Q5 | Loans issued on one day | Daily circulation report |

## 4. Optimisation decisions

| Query | Before (typical plan) | Change | After (typical plan) |
|---|---|---|---|
| Q1 | Parallel **Seq Scan** on `loans`, because `member_id` has no index (PostgreSQL does not index foreign keys automatically) | `idx_loans_member_id` | **Bitmap Index Scan**, reading only that member's ~40 rows |
| Q2 | Already uses an index scan on the partial unique index from Portfolio 1 | None needed | Unchanged. A separate partial index was tested and the planner ignored it, so it was not kept |
| Q3 | Seq Scan on all 200,000 loans, aggregated | `idx_loans_copy_id` plus a **materialised view** `mv_top_books` | Index barely helps, because every row must be counted. The materialised view returns the answer by reading 10 precomputed rows |
| Q4 | Seq Scan on `fines` with a date filter | `idx_fines_assessed_date` | Bitmap Index Scan on the date range |
| Q5 | Parallel Seq Scan on `loans` with an equality filter on date | `idx_loans_loan_date` | Bitmap Index Scan |

## 5. Performance results 

Copy the `Execution Time` line from your own `plans_before.txt` and `plans_after.txt`:

| Query | Before (ms) | After (ms) | Speed-up | What was applied |
|---|---|---|---|---|
| Q1 | 456.142 | 3.398 | about 134x | Index |
| Q2 | 4.204 | 3.849 | about 1.1x (no real change) | None (already covered by existing index) |
| Q3 (index only) | 253.758 | 225.992 | about 1.1x | Index |
| Q3 (materialised view) | 253.758 | about 0.42 | about 600x | Materialised view |
| Q4 | 18.227 | 4.698 | about 3.9x | Index |
| Q5 | 306.621 | 0.727 | about 420x | Index |


## 6. Performance analysis 
Indexes gave the biggest gains where a query picks out a small number of rows from a large table. Q1 (456 ms to 3.4 ms) and Q5 (306 ms to 0.7 ms) went from a Sequential Scan, which reads every row, to an Index Scan, which goes straight to the matching rows. Q2 did not need a new index, because the partial unique index from Portfolio 1 already covers it, and adding another would only slow inserts and updates and use more space. Q3 aggregates over every loan, so an index cannot skip that work (254 ms to 226 ms). A materialised view fixed it (about 0.4 ms) by storing the finished result, but the trade-off is that the stored result goes stale and needs REFRESH MATERIALIZED VIEW. Overall, indexes cost storage and slow down writes, so they are worth adding only for queries that run often and take a long time on large tables.

## 7. Technical Reflection 
The big improvement for Q1 (456 ms to 3.4 ms) and Q5 (306 ms to 0.7 ms) came from adding indexes on the columns the queries use. Before indexing, PostgreSQL performed a Sequential Scan, reading through the table to find the records it needed. After indexing, it used an Index Scan to go straight to the matching records without checking the whole table. The indexes made little difference to Q2 and Q3, because an index only helps locate records and does not reduce the other work those queries do on large numbers of rows. The materialised view worked much better for Q3 (about 0.4 ms) because it stores the result in advance, so PostgreSQL does not repeat the same calculation each time. Indexes also have a cost: they take extra storage and slow down inserts, updates and deletes, because the indexes must be maintained as well. I would add an index only to queries that run often and take a long time on large amounts of data, not to queries that are already fast.