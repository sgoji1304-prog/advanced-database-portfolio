-- =====================================================================
-- MIT 8103 Advanced Database Systems | Portfolio 1: Database Design
-- Case study : CityLib Public Library (simulated library management system)
-- DBMS       : PostgreSQL 14+
-- Usage      : createdb citylib && psql -d citylib -f schema.sql
-- =====================================================================

DROP TABLE IF EXISTS fines        CASCADE;
DROP TABLE IF EXISTS loans        CASCADE;
DROP TABLE IF EXISTS book_copies  CASCADE;
DROP TABLE IF EXISTS book_authors CASCADE;
DROP TABLE IF EXISTS books        CASCADE;
DROP TABLE IF EXISTS authors      CASCADE;
DROP TABLE IF EXISTS categories   CASCADE;
DROP TABLE IF EXISTS members      CASCADE;
DROP TABLE IF EXISTS staff        CASCADE;

-- ---------- Reference / lookup tables ----------
CREATE TABLE categories (
    category_id  SERIAL       PRIMARY KEY,
    name         VARCHAR(60)  NOT NULL UNIQUE
);

CREATE TABLE authors (
    author_id    SERIAL       PRIMARY KEY,
    full_name    VARCHAR(120) NOT NULL
);

-- ---------- Catalogue ----------
-- A "book" is the title/edition; physical items are in book_copies.
CREATE TABLE books (
    book_id           SERIAL       PRIMARY KEY,
    isbn              CHAR(13)     NOT NULL UNIQUE,
    title             VARCHAR(200) NOT NULL,
    publication_year  SMALLINT     CHECK (publication_year BETWEEN 1400 AND 2100),
    category_id       INT          NOT NULL
                      REFERENCES categories(category_id)
                      ON UPDATE CASCADE ON DELETE RESTRICT
);

-- Many-to-many: a book can have several authors, an author several books.
CREATE TABLE book_authors (
    book_id    INT NOT NULL REFERENCES books(book_id)     ON DELETE CASCADE,
    author_id  INT NOT NULL REFERENCES authors(author_id) ON DELETE RESTRICT,
    PRIMARY KEY (book_id, author_id)
);

-- Physical copies that can actually be borrowed.
CREATE TABLE book_copies (
    copy_id   SERIAL      PRIMARY KEY,
    book_id   INT         NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
    barcode   VARCHAR(20) NOT NULL UNIQUE,
    status    VARCHAR(12) NOT NULL DEFAULT 'available'
              CHECK (status IN ('available', 'on_loan', 'lost', 'damaged'))
);

-- ---------- People ----------
CREATE TABLE members (
    member_id    SERIAL       PRIMARY KEY,
    full_name    VARCHAR(120) NOT NULL,
    email        VARCHAR(150) NOT NULL UNIQUE,
    phone        VARCHAR(20),
    joined_date  DATE         NOT NULL DEFAULT CURRENT_DATE,
    status       VARCHAR(10)  NOT NULL DEFAULT 'active'
                 CHECK (status IN ('active', 'suspended', 'expired'))
);

CREATE TABLE staff (
    staff_id   SERIAL       PRIMARY KEY,
    full_name  VARCHAR(120) NOT NULL,
    role       VARCHAR(20)  NOT NULL
               CHECK (role IN ('librarian', 'assistant', 'admin')),
    email      VARCHAR(150) NOT NULL UNIQUE
);

-- ---------- Transactions ----------
CREATE TABLE loans (
    loan_id      SERIAL  PRIMARY KEY,
    copy_id      INT     NOT NULL REFERENCES book_copies(copy_id),
    member_id    INT     NOT NULL REFERENCES members(member_id),
    staff_id     INT     NOT NULL REFERENCES staff(staff_id),
    loan_date    DATE    NOT NULL DEFAULT CURRENT_DATE,
    due_date     DATE    NOT NULL,
    return_date  DATE,
    CONSTRAINT chk_due_after_loan    CHECK (due_date >= loan_date),
    CONSTRAINT chk_return_after_loan CHECK (return_date IS NULL OR return_date >= loan_date)
);

-- Business rule enforced by the database itself:
-- a physical copy can have at most ONE active (unreturned) loan at a time.
CREATE UNIQUE INDEX uq_one_active_loan_per_copy
    ON loans (copy_id) WHERE return_date IS NULL;

CREATE TABLE fines (
    fine_id        SERIAL        PRIMARY KEY,
    loan_id        INT           NOT NULL UNIQUE REFERENCES loans(loan_id),
    amount         NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    assessed_date  DATE          NOT NULL DEFAULT CURRENT_DATE,
    paid           BOOLEAN       NOT NULL DEFAULT FALSE
);
