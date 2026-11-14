-- =====================================================================
-- Execution plans for Q1-Q5.
-- Run TWICE: once before indexes.sql and once after, saving each output:
--   psql -d citylib -f explain.sql > results/plans_before.txt
--   psql -d citylib -f indexes.sql
--   psql -d citylib -f explain.sql > results/plans_after.txt
-- =====================================================================
\echo '=================== Q1: member loan history ==================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT l.loan_id, b.title, l.loan_date, l.due_date, l.return_date
FROM loans l
JOIN book_copies c ON c.copy_id = l.copy_id
JOIN books b       ON b.book_id = c.book_id
WHERE l.member_id = 1234
ORDER BY l.loan_date DESC;

\echo '=================== Q2: overdue loans ==================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT l.loan_id, m.full_name, m.email, b.title,
       CURRENT_DATE - l.due_date AS days_overdue
FROM loans l
JOIN members m     ON m.member_id = l.member_id
JOIN book_copies c ON c.copy_id   = l.copy_id
JOIN books b       ON b.book_id   = c.book_id
WHERE l.return_date IS NULL
  AND l.due_date < CURRENT_DATE
ORDER BY days_overdue DESC;

\echo '=================== Q3: top 10 most borrowed ==================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.book_id, b.title, COUNT(*) AS times_borrowed
FROM loans l
JOIN book_copies c ON c.copy_id = l.copy_id
JOIN books b       ON b.book_id = c.book_id
GROUP BY b.book_id, b.title
ORDER BY times_borrowed DESC
LIMIT 10;

\echo '=================== Q4: fines per day (one week) ==================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT assessed_date, COUNT(*) AS fines_count, SUM(amount) AS total_amount
FROM fines
WHERE assessed_date BETWEEN CURRENT_DATE - 60 AND CURRENT_DATE - 54
GROUP BY assessed_date
ORDER BY assessed_date;

\echo '=================== Q5: loans issued on one day ==================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT l.loan_id, l.copy_id, l.member_id, l.due_date
FROM loans l
WHERE l.loan_date = CURRENT_DATE - 100;
