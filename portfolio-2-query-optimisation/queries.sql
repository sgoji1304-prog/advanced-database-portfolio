-- =====================================================================
-- Portfolio 2: Query Processing and Optimisation (CityLib)
-- The five business queries used for analysis. Run in psql against
-- the database created in Portfolio 1.
-- =====================================================================

-- Q1. Loan history of one member (most recent first)
SELECT l.loan_id, b.title, l.loan_date, l.due_date, l.return_date
FROM loans l
JOIN book_copies c ON c.copy_id = l.copy_id
JOIN books b       ON b.book_id = c.book_id
WHERE l.member_id = 1234
ORDER BY l.loan_date DESC;

-- Q2. All overdue, unreturned loans with member contact details
SELECT l.loan_id, m.full_name, m.email, b.title,
       CURRENT_DATE - l.due_date AS days_overdue
FROM loans l
JOIN members m     ON m.member_id = l.member_id
JOIN book_copies c ON c.copy_id   = l.copy_id
JOIN books b       ON b.book_id   = c.book_id
WHERE l.return_date IS NULL
  AND l.due_date < CURRENT_DATE
ORDER BY days_overdue DESC;

-- Q3. Ten most borrowed books of all time
SELECT b.book_id, b.title, COUNT(*) AS times_borrowed
FROM loans l
JOIN book_copies c ON c.copy_id = l.copy_id
JOIN books b       ON b.book_id = c.book_id
GROUP BY b.book_id, b.title
ORDER BY times_borrowed DESC
LIMIT 10;

-- Q4. Fines assessed per day over one week (finance report)
SELECT assessed_date, COUNT(*) AS fines_count, SUM(amount) AS total_amount
FROM fines
WHERE assessed_date BETWEEN CURRENT_DATE - 60 AND CURRENT_DATE - 54
GROUP BY assessed_date
ORDER BY assessed_date;

-- Q5. Loans issued on one specific day (daily circulation report)
SELECT l.loan_id, l.copy_id, l.member_id, l.due_date
FROM loans l
WHERE l.loan_date = CURRENT_DATE - 100;
