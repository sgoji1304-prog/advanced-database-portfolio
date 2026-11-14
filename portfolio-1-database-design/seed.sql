-- =====================================================================
-- Seed data for CityLib (synthetic). Run AFTER schema.sql.
-- Volumes: 8 categories, 300 authors, 2,000 books, 6,000 copies,
--          5,000 members, 10 staff, ~200,000 loans, fines for late returns.
-- All data is generated with generate_series(); nothing is real.
-- =====================================================================

INSERT INTO categories (name) VALUES
 ('Fiction'), ('Science'), ('Technology'), ('History'),
 ('Biography'), ('Children'), ('Law'), ('Business');

INSERT INTO authors (full_name)
SELECT 'Author ' || g FROM generate_series(1, 300) g;

INSERT INTO books (isbn, title, publication_year, category_id)
SELECT '978' || lpad(g::text, 10, '0'),
       'Book Title ' || g,
       1980 + (g % 45),
       1 + (g % 8)
FROM generate_series(1, 2000) g;

-- every book has one author; every 5th book has a second (always different) one
INSERT INTO book_authors (book_id, author_id)
SELECT g, 1 + (g % 300) FROM generate_series(1, 2000) g;

INSERT INTO book_authors (book_id, author_id)
SELECT g, 1 + ((g + 150) % 300) FROM generate_series(1, 2000) g WHERE g % 5 = 0;

INSERT INTO book_copies (book_id, barcode, status)
SELECT 1 + (g % 2000), 'BC' || lpad(g::text, 6, '0'), 'available'
FROM generate_series(1, 6000) g;

INSERT INTO members (full_name, email, phone, joined_date, status)
SELECT 'Member ' || g,
       'member' || g || '@citylib.example',
       '080' || lpad((10000000 + g)::text, 8, '0'),
       CURRENT_DATE - (g % 1500),
       CASE WHEN g % 50 = 0 THEN 'suspended' ELSE 'active' END
FROM generate_series(1, 5000) g;

INSERT INTO staff (full_name, role, email)
SELECT 'Staff ' || g,
       CASE WHEN g = 1 THEN 'admin' WHEN g <= 5 THEN 'librarian' ELSE 'assistant' END,
       'staff' || g || '@citylib.example'
FROM generate_series(1, 10) g;

-- ---------- Historic (returned) loans: 200,000 ----------
INSERT INTO loans (copy_id, member_id, staff_id, loan_date, due_date, return_date)
SELECT 1 + (g * 7 % 6000),
       1 + (g * 7919 % 5000),
       1 + (g % 10),
       d,
       d + 14,
       d + (g % 25)            -- returns 0..24 days after loan; >14 means late
FROM (
    SELECT g, CURRENT_DATE - (30 + g % 700) AS d
    FROM generate_series(1, 200000) g
) t;

-- ---------- Active loans: copies 1..50 on time, 51..80 overdue ----------
INSERT INTO loans (copy_id, member_id, staff_id, loan_date, due_date, return_date)
SELECT g, 1 + (g * 37 % 5000), 1 + (g % 10),
       CURRENT_DATE - 5, CURRENT_DATE + 9, NULL
FROM generate_series(1, 50) g;

INSERT INTO loans (copy_id, member_id, staff_id, loan_date, due_date, return_date)
SELECT g, 1 + (g * 37 % 5000), 1 + (g % 10),
       CURRENT_DATE - 40, CURRENT_DATE - 26, NULL
FROM generate_series(51, 80) g;

UPDATE book_copies SET status = 'on_loan'
WHERE copy_id IN (SELECT copy_id FROM loans WHERE return_date IS NULL);

-- ---------- Fines: 50 per day late, for every late return ----------
INSERT INTO fines (loan_id, amount, assessed_date, paid)
SELECT loan_id,
       (return_date - due_date) * 50.00,
       return_date,
       (loan_id % 3 = 0)
FROM loans
WHERE return_date IS NOT NULL AND return_date > due_date;

ANALYZE;
