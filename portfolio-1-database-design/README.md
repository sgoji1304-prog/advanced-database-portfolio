# Portfolio 1: Database Design and Modelling

## 1. Selected Case Study

| Item | Description |
|---|---|
| **Organisation** | **CityLib Public Library** (a simulated municipal library) |
| **Nature of the system** | Library management: cataloguing books, lending physical copies to members, tracking returns and charging fines for late returns |
| **Users of the database** | Members (borrowers), librarians and library assistants, library administrators |
| **Major data stored** | Books, authors, categories, physical book copies, members, staff, loans, fines |
| **Key operations** | Search the catalogue, borrow a book, return a book, calculate and record a fine, list overdue loans, report most borrowed books |

All five portfolios in this repository use this same case study.

## 2. ER Diagram


erDiagram
    CATEGORIES ||--o{ BOOKS : classifies
    BOOKS ||--o{ BOOK_AUTHORS : "is written by"
    AUTHORS ||--o{ BOOK_AUTHORS : writes
    BOOKS ||--|{ BOOK_COPIES : "has physical"
    BOOK_COPIES ||--o{ LOANS : "is lent in"
    MEMBERS ||--o{ LOANS : borrows
    STAFF ||--o{ LOANS : issues
    LOANS ||--o| FINES : "may incur"

    CATEGORIES { int category_id PK
                 string name UK }
    AUTHORS { int author_id PK
              string full_name }
    BOOKS { int book_id PK
            char isbn UK
            string title
            int publication_year
            int category_id FK }
    BOOK_AUTHORS { int book_id PK,FK
                   int author_id PK,FK }
    BOOK_COPIES { int copy_id PK
                  int book_id FK
                  string barcode UK
                  string status }
    MEMBERS { int member_id PK
              string full_name
              string email UK
              string phone
              date joined_date
              string status }
    STAFF { int staff_id PK
            string full_name
            string role
            string email UK }
    LOANS { int loan_id PK
            int copy_id FK
            int member_id FK
            int staff_id FK
            date loan_date
            date due_date
            date return_date }
    FINES { int fine_id PK
            int loan_id FK,UK
            numeric amount
            date assessed_date
            boolean paid }
```

> **Evidence to capture:**
## 3. Relational Schema

Full DDL is in [`schema.sql`](schema.sql). Summary (PK = primary key, FK = foreign key, UK = unique):

```
categories   (category_id PK, name UK)
authors      (author_id PK, full_name)
books        (book_id PK, isbn UK, title, publication_year, category_id FK -> categories)
book_authors (book_id PK/FK -> books, author_id PK/FK -> authors)
book_copies  (copy_id PK, book_id FK -> books, barcode UK, status)
members      (member_id PK, full_name, email UK, phone, joined_date, status)
staff        (staff_id PK, full_name, role, email UK)
loans        (loan_id PK, copy_id FK -> book_copies, member_id FK -> members,
              staff_id FK -> staff, loan_date, due_date, return_date)
fines        (fine_id PK, loan_id FK/UK -> loans, amount, assessed_date, paid)
```

## 4. Keys and Constraints

| Type | Where | Purpose |
|---|---|---|
| Primary keys | Every table (`SERIAL`); composite PK on `book_authors` | Unique row identity |
| Foreign keys | `books.category_id`, `book_authors.*`, `book_copies.book_id`, `loans.copy_id/member_id/staff_id`, `fines.loan_id` | Referential integrity; `RESTRICT` stops deleting data still in use, `CASCADE` on `book_authors`/`book_copies` removes dependent rows with their book |
| UNIQUE | `isbn`, `barcode`, member `email`, staff `email`, category `name`, `fines.loan_id` | No duplicates; `fines.loan_id` makes the loan-to-fine link one-to-one |
| CHECK | `copy status`, `member status`, `staff role`, `publication_year` range, `fines.amount >= 0` | Domain validation |
| CHECK (row-level) | `due_date >= loan_date`, `return_date >= loan_date` | Dates must be logical |
| NOT NULL / DEFAULT | All mandatory columns, `status` and date defaults | Required data present |
| **Partial unique index** | `uq_one_active_loan_per_copy ON loans(copy_id) WHERE return_date IS NULL` | The database itself guarantees a copy can only have one unreturned loan, so even a buggy application cannot double-lend a copy |

## 5. Normalisation Explanation

**Starting point (unnormalised).** Imagine the library kept everything in one sheet:

`Loan(loan_id, member_name, member_email, book_title, isbn, author1, author2, category, copy_barcode, staff_name, loan_date, due_date, return_date, fine_amount)`

Problems: member and book details repeat on every loan (update anomaly), a new book cannot be recorded before it is lent (insert anomaly), deleting the last loan of a book loses the book (delete anomaly), and `author1`/`author2` is a repeating group.

**1NF: atomic values, no repeating groups.** Authors were pulled out of the repeating `author1/author2` columns. Because a book can have many authors and an author many books, this is many-to-many and is resolved with the junction table `book_authors`. Every column holds a single value.

**2NF: no partial dependency on part of a composite key.** In `book_authors` the key is `(book_id, author_id)` and it has no other columns, so nothing depends on only half the key. Book attributes (`title`, `isbn`, `publication_year`) depend on `book_id` alone, so they live in `books`, not in the loan row.

**3NF: no transitive dependencies.** Examples of what was removed:
- `category_name` depended on `category_id`, which depends on the book, so it moved to `categories`.
- Physical details (`barcode`, `status`) describe a *copy*, not a *title*, so `book_copies` is separate from `books`. This lets the library own several copies of one title.
- Member and staff details depend on their own IDs, not on the loan, so they sit in `members` and `staff`.
- `fine_amount` depends on a specific loan being late, and not every loan has one, so `fines` is a separate table. This avoids NULL-heavy loan rows.

**Result.** Every non-key attribute depends on the key, the whole key, and nothing but the key (3NF). Each fact is stored once.

**Deliberate design decision.** `fines.amount` is a value derived from `return_date - due_date`. It is stored deliberately because the fine rate may change over time and the amount charged at the time must remain a historical fact. Likewise `book_copies.status` could be derived from `loans`, but it is kept for fast availability checks; Portfolio 3 shows how it is kept consistent with transactions.

## 6. How This Was Implemented and Tested

```bash
createdb citylib
psql -d citylib -f schema.sql      # creates 9 tables, constraints, partial unique index
psql -d citylib -f seed.sql        # loads synthetic data (about 200,000 loans, takes a few seconds)
```

Verification query (expected: loans = 200,080, active loans = 80, fines = 80,000):

```sql
SELECT 'loans', count(*) FROM loans
UNION ALL SELECT 'active loans', count(*) FROM loans WHERE return_date IS NULL
UNION ALL SELECT 'fines', count(*) FROM fines;
```

**Constraint tests** 

```sql
-- 1. due date before loan date
INSERT INTO loans (copy_id, member_id, staff_id, loan_date, due_date) VALUES (100, 1, 1, '2026-11-10', '2026-11-01');
-- 2. invalid status
UPDATE book_copies SET status = 'stolen' WHERE copy_id = 1;
-- 3. duplicate ISBN
INSERT INTO books (isbn, title, category_id) VALUES ('9780000000001', 'Duplicate', 1);
-- 4. lending a copy that is already on loan (copy 1 has an active loan)
INSERT INTO loans (copy_id, member_id, staff_id, due_date) VALUES (1, 2, 1, CURRENT_DATE + 14);
-- 5. deleting a category that is in use
DELETE FROM categories WHERE category_id = 1;
```

## 7. Technical Reflection 

The hardest part of the design was deciding how to structure the tables and connect them properly, especially the relationship between books, authors and physical copies. I had to make sure each relationship was correct and that every table had the right primary and foreign keys. The five constraint tests showed me how much constraints matter for preventing bad data: the database rejected an invalid due date, an incorrect loan status and a duplicate ISBN. It also stopped the same copy from being loaned to two people at once, and it refused to delete a category that still had books linked to it. This matters for a library because it needs accurate, reliable records of its books, members and loans. Without these rules the database could hold duplicate books, wrong loan records or conflicting borrowing information, which would cause problems for both librarians and members.