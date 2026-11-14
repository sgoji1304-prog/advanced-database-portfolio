-- =====================================================================
-- Demonstrates COMMIT, ROLLBACK, atomicity on failure, and SAVEPOINT.
-- Run with:  psql -d citylib -f 02_commit_rollback.sql
-- NOTE: do NOT use ON_ERROR_STOP for this file. Some statements are
--       SUPPOSED to fail so we can show the rollback.
-- Requires 01_functions.sql to have been run first.
-- =====================================================================
\set QUIET on
\pset border 2

\echo
\echo '#### Setup: reset copies 500 and 600 and remove test loans from earlier runs'
-- seed.sql creates loans 1..200080; anything above that was made by this demo.
DELETE FROM fines WHERE loan_id IN (SELECT loan_id FROM loans WHERE copy_id IN (500, 600) AND loan_id > 200080);
DELETE FROM loans WHERE copy_id IN (500, 600) AND loan_id > 200080;
UPDATE book_copies SET status = 'available' WHERE copy_id IN (500, 600);

-- ---------------------------------------------------------------------
\echo
\echo '#### 1. COMMIT: a successful borrow is saved permanently'
BEGIN;
SELECT borrow_book(500, 2, 1) AS new_loan_id;
\echo 'Inside the transaction we can see the loan and the copy status:'
SELECT l.loan_id, l.copy_id, l.member_id, l.due_date, c.status AS copy_status
FROM loans l JOIN book_copies c USING (copy_id) WHERE l.copy_id = 500 AND l.return_date IS NULL;
COMMIT;
\echo 'After COMMIT (visible to every other session):'
SELECT copy_id, status FROM book_copies WHERE copy_id = 500;

-- ---------------------------------------------------------------------
\echo
\echo '#### 2. ROLLBACK: an explicit rollback undoes everything'
BEGIN;
UPDATE book_copies SET status = 'lost' WHERE copy_id = 600;
\echo 'Inside the transaction the copy looks lost:'
SELECT copy_id, status FROM book_copies WHERE copy_id = 600;
ROLLBACK;
\echo 'After ROLLBACK the change never happened:'
SELECT copy_id, status FROM book_copies WHERE copy_id = 600;

-- ---------------------------------------------------------------------
\echo
\echo '#### 3. ATOMICITY: when one statement fails, earlier ones are undone too'
\echo 'Step A marks copy 600 on_loan (succeeds). Step B tries to lend copy 500,'
\echo 'which is already on loan (violates the one-active-loan rule and FAILS).'
BEGIN;
UPDATE book_copies SET status = 'on_loan' WHERE copy_id = 600;
INSERT INTO loans (copy_id, member_id, staff_id, due_date) VALUES (500, 3, 1, CURRENT_DATE + 14);
-- The transaction is now aborted. Further statements are rejected until ROLLBACK:
SELECT 'this statement is ignored' AS note;
ROLLBACK;
\echo 'Copy 600 is STILL available, because step A was rolled back with step B:'
SELECT copy_id, status FROM book_copies WHERE copy_id = 600;

-- ---------------------------------------------------------------------
\echo
\echo '#### 4. Business rule failure inside a function rolls back automatically'
SELECT borrow_book(500, 3, 1);   -- copy 500 is on_loan after demo 1, so this raises an exception
\echo 'No second loan was created for copy 500 (expect exactly 1 open loan):'
SELECT count(*) AS open_loans_on_copy_500 FROM loans WHERE copy_id = 500 AND return_date IS NULL;

-- ---------------------------------------------------------------------
\echo
\echo '#### 5. SAVEPOINT: roll back only part of a transaction'
BEGIN;
SELECT borrow_book(600, 4, 1) AS loan_for_copy_600;
SAVEPOINT after_first_loan;
SELECT borrow_book(500, 4, 1);          -- fails: copy 500 not available
ROLLBACK TO SAVEPOINT after_first_loan; -- undo only the failed part
\echo 'The first loan (copy 600) is still alive inside the transaction:'
SELECT copy_id, status FROM book_copies WHERE copy_id = 600;
COMMIT;
SELECT copy_id, status FROM book_copies WHERE copy_id IN (500, 600) ORDER BY copy_id;

-- ---------------------------------------------------------------------
\echo
\echo '#### 6. return_book: on-time return, then a late return with a fine'
SELECT return_book(l.loan_id) AS fine_for_copy_600
FROM loans l WHERE l.copy_id = 600 AND l.return_date IS NULL;

-- make the loan on copy 500 look 10 days overdue, then return it
UPDATE loans SET loan_date = CURRENT_DATE - 24, due_date = CURRENT_DATE - 10
WHERE copy_id = 500 AND return_date IS NULL;
SELECT return_book(l.loan_id) AS fine_for_copy_500 FROM loans l
WHERE l.copy_id = 500 AND l.return_date IS NULL;   -- expect 500.00 (10 days x 50)

SELECT f.fine_id, f.loan_id, f.amount, f.paid
FROM fines f JOIN loans l USING (loan_id) WHERE l.copy_id = 500 ORDER BY f.fine_id DESC LIMIT 1;
SELECT copy_id, status FROM book_copies WHERE copy_id IN (500, 600) ORDER BY copy_id;
