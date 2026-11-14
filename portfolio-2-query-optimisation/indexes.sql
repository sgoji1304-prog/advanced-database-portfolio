-- =====================================================================
-- Optimisation: indexes chosen from the "before" execution plans.
-- Run after saving plans_before.txt, then re-run explain.sql.
-- =====================================================================

-- Q1: PostgreSQL does NOT automatically index foreign key columns.
--     loans.member_id was being scanned sequentially across all loans.
CREATE INDEX idx_loans_member_id ON loans (member_id);

-- Q1 / Q3: joining loans to book_copies on copy_id (the existing partial
--     unique index only covers unreturned loans, so it cannot serve full joins).
CREATE INDEX idx_loans_copy_id ON loans (copy_id);

-- Q2: NO new index. Only ~80 of 200,000 loans are unreturned, and the partial
--     unique index from Portfolio 1 (uq_one_active_loan_per_copy ... WHERE
--     return_date IS NULL) already lets PostgreSQL find exactly those rows.
--     An extra partial index on due_date was tested and the planner ignored it,
--     so it was dropped: unused indexes only slow down writes.

-- Q4: range filter on the fines date.
CREATE INDEX idx_fines_assessed_date ON fines (assessed_date);

-- Q5: equality filter on loan date.
CREATE INDEX idx_loans_loan_date ON loans (loan_date);

-- Q3 (aggregation over all loans): indexes help little because every row
-- must be counted. A materialised view precomputes the result instead.
DROP MATERIALIZED VIEW IF EXISTS mv_top_books;
CREATE MATERIALIZED VIEW mv_top_books AS
SELECT b.book_id, b.title, COUNT(*) AS times_borrowed
FROM loans l
JOIN book_copies c ON c.copy_id = l.copy_id
JOIN books b       ON b.book_id = c.book_id
GROUP BY b.book_id, b.title;

CREATE INDEX idx_mv_top_books_count ON mv_top_books (times_borrowed DESC);

ANALYZE;

-- Compare Q3 against the materialised view:
--   EXPLAIN (ANALYZE, BUFFERS)
--   SELECT book_id, title, times_borrowed FROM mv_top_books
--   ORDER BY times_borrowed DESC LIMIT 10;
-- Refresh when data changes:  REFRESH MATERIALIZED VIEW mv_top_books;
