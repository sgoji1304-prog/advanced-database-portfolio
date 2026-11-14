-- =====================================================================
-- Portfolio 4: export the relational catalogue as JSON documents, one per
-- line (JSON Lines). Each book becomes ONE document with its authors and
-- physical copies EMBEDDED, replacing three joins with a single read.
--
-- Run from THIS folder so books.jsonl is created next to mongo_setup.js:
--     psql -d citylib -f export_from_postgres.sql
-- =====================================================================
\pset format unaligned
\pset tuples_only on
\pset footer off
\o books.jsonl

SELECT json_build_object(
         '_id',              b.book_id,
         'isbn',             b.isbn,
         'title',            b.title,
         'publication_year', b.publication_year,
         'category',         c.name,
         'authors', (SELECT json_agg(json_build_object('author_id', a.author_id, 'name', a.full_name)
                                     ORDER BY a.author_id)
                     FROM book_authors ba JOIN authors a ON a.author_id = ba.author_id
                     WHERE ba.book_id = b.book_id),
         'copies',  (SELECT json_agg(json_build_object('copy_id', bc.copy_id, 'barcode', bc.barcode,
                                                       'status', bc.status)
                                     ORDER BY bc.copy_id)
                     FROM book_copies bc WHERE bc.book_id = b.book_id)
       )
FROM books b
JOIN categories c ON c.category_id = b.category_id
ORDER BY b.book_id;

\o
\pset format aligned
\pset tuples_only off
\pset footer on
\echo 'Wrote books.jsonl (one JSON document per line)'
