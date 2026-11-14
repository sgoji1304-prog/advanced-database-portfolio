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

Run `explain.sql` twice before indexing and use the second result, so caches are warm and the comparison is fair. Screenshot the "before" and "after" plan for Q1 at minimum, and keep the full text files in `results/`.

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

## 5. Performance results (fill in with YOUR measurements)

Copy the `Execution Time` line from your own `plans_before.txt` and `plans_after.txt`:

| Query | Before (ms) | After (ms) | Plan change | Improvement |
|---|---|---|---|---|
| Q1 | | | Seq Scan to Index Scan | |
| Q2 | | | unchanged | |
| Q3 (index only) | | | little change | |
| Q3 (materialised view) | | | full aggregation to 10-row read | |
| Q4 | | | Seq Scan to Index Scan | |
| Q5 | | | Seq Scan to Index Scan | |

> In the reference run used to test these scripts, Q1, Q4 and Q5 became roughly 10-25 times faster, Q2 was unchanged, Q3 improved only slightly with indexes, and the materialised view made Q3 effectively instant. Your exact numbers will differ with your machine, so **submit your own measurements, not these.**

## 6. Performance analysis (write in your own words, using your numbers)

Points the analysis should cover:

1. **Why the index helped.** A sequential scan reads every page of the table, while a B-tree index goes straight to matching rows. The gain is largest when the filter is *selective* (Q1 returns about 40 of 200,000 rows; Q5 about 290).
2. **Why Q2 did not need a new index.** The Portfolio 1 partial unique index already covers `WHERE return_date IS NULL`. Adding another was redundant, and every extra index slows `INSERT`/`UPDATE` and uses space.
3. **Why Q3 is different.** An aggregate over the whole table must read every loan, so an index cannot skip work. The right tool is precomputation (materialised view). The trade-off is staleness, so it needs `REFRESH MATERIALIZED VIEW`.
4. **Reading the plan.** Mention `cost`, `actual time`, `rows` estimated versus actual, and `Buffers` (pages read). Run `ANALYZE` after bulk loads so the planner's estimates are accurate.
5. **Trade-offs.** Indexes speed reads but cost write time and disk space, so index only what the workload needs.

## 7. Technical Reflection (draft, rewrite in your own words)

*Add 3-5 sentences about the most surprising result (for example, Q2 needing no change, or Q3 not benefiting from an index) and what you learned about reading execution plans.*
