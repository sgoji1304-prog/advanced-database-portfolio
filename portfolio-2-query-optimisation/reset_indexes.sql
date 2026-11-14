-- Removes the optimisation objects so you can re-run the before/after comparison.
DROP MATERIALIZED VIEW IF EXISTS mv_top_books;
DROP INDEX IF EXISTS idx_loans_member_id;
DROP INDEX IF EXISTS idx_loans_copy_id;
DROP INDEX IF EXISTS idx_fines_assessed_date;
DROP INDEX IF EXISTS idx_loans_loan_date;
ANALYZE;
