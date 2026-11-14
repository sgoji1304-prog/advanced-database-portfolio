-- =====================================================================
-- Portfolio 3: Transactions and Concurrency (CityLib)
-- Business operations written as atomic units of work.
-- A PL/pgSQL function always runs inside a transaction: if it raises an
-- exception, EVERYTHING it did is rolled back automatically.
-- =====================================================================

-- ---------------------------------------------------------------------
-- borrow_book: lend one copy to one member.
-- Rules: copy must be available; member must be active; max 5 open loans.
-- Concurrency: row locks (FOR UPDATE) make competing borrowers queue up
-- instead of both passing the same checks at the same moment.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION borrow_book(p_copy_id INT, p_member_id INT, p_staff_id INT)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_copy_status   TEXT;
    v_member_status TEXT;
    v_open_loans    INT;
    v_loan_id       INT;
BEGIN
    -- Lock the copy row: a second borrower of the SAME copy waits here.
    SELECT status INTO v_copy_status
    FROM book_copies WHERE copy_id = p_copy_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Copy % does not exist', p_copy_id;
    END IF;
    IF v_copy_status <> 'available' THEN
        RAISE EXCEPTION 'Copy % is not available (status: %)', p_copy_id, v_copy_status;
    END IF;

    -- Lock the member row: two simultaneous borrows by the SAME member are
    -- serialised, so the 5-loan limit cannot be bypassed by a race.
    SELECT status INTO v_member_status
    FROM members WHERE member_id = p_member_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Member % does not exist', p_member_id;
    END IF;
    IF v_member_status <> 'active' THEN
        RAISE EXCEPTION 'Member % is % and cannot borrow', p_member_id, v_member_status;
    END IF;

    SELECT COUNT(*) INTO v_open_loans
    FROM loans WHERE member_id = p_member_id AND return_date IS NULL;
    IF v_open_loans >= 5 THEN
        RAISE EXCEPTION 'Member % already has % open loans (limit 5)', p_member_id, v_open_loans;
    END IF;

    INSERT INTO loans (copy_id, member_id, staff_id, loan_date, due_date)
    VALUES (p_copy_id, p_member_id, p_staff_id, CURRENT_DATE, CURRENT_DATE + 14)
    RETURNING loan_id INTO v_loan_id;

    UPDATE book_copies SET status = 'on_loan' WHERE copy_id = p_copy_id;

    RETURN v_loan_id;
END;
$$;

-- ---------------------------------------------------------------------
-- return_book: close a loan, free the copy, and record a fine (50 per day
-- late) when applicable. Returns the fine amount (0 if on time).
-- Three writes (loan, copy, fine) succeed or fail together.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION return_book(p_loan_id INT)
RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE
    v_copy_id INT;
    v_due     DATE;
    v_return  DATE;
    v_fine    NUMERIC := 0;
BEGIN
    SELECT copy_id, due_date, return_date INTO v_copy_id, v_due, v_return
    FROM loans WHERE loan_id = p_loan_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan % does not exist', p_loan_id;
    END IF;
    IF v_return IS NOT NULL THEN
        RAISE EXCEPTION 'Loan % was already returned on %', p_loan_id, v_return;
    END IF;

    UPDATE loans        SET return_date = CURRENT_DATE WHERE loan_id = p_loan_id;
    UPDATE book_copies  SET status = 'available'       WHERE copy_id = v_copy_id;

    IF CURRENT_DATE > v_due THEN
        v_fine := (CURRENT_DATE - v_due) * 50.00;
        INSERT INTO fines (loan_id, amount) VALUES (p_loan_id, v_fine);
    END IF;

    RETURN v_fine;
END;
$$;
