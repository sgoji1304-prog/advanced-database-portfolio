# Portfolio 4: NoSQL and Advanced Data Models

Case study: **CityLib Public Library**. NoSQL model: **document database (MongoDB)**, built from the same catalogue data as the PostgreSQL database in Portfolio 1.

## 1. Files

| File | Purpose |
|---|---|
| `export_from_postgres.sql` | Exports each book (with its authors and copies embedded) from PostgreSQL as one JSON document per line |
| `mongo_setup.js` | Loads the export into MongoDB, enriches it with flexible fields, creates indexes |
| `mongo_queries.js` | Queries, aggregations, an atomic update, and before/after index evidence |

## 2. How to run

```bash
# 1. Export from PostgreSQL (creates books.jsonl in this folder)
psql -d citylib -f export_from_postgres.sql

# 2. Load into MongoDB
mongosh "mongodb://localhost:27017/citylib_nosql" --file mongo_setup.js

# 3. Run the queries and capture the output
mongosh "mongodb://localhost:27017/citylib_nosql" --file mongo_queries.js > results.txt
```

Run the commands from this folder. Screenshot the output of steps 2 and 3, and keep `results.txt`.

## 3. Document model

One `books` collection. Each document holds everything usually read together:

```json
{
  "_id": 7,
  "isbn": "9780000000007",
  "title": "Book Title 7",
  "publication_year": 1987,
  "category": "Business",
  "authors": [ { "author_id": 8, "name": "Author 8" } ],
  "copies":  [ { "copy_id": 6,    "barcode": "BC000006", "status": "on_loan"   },
               { "copy_id": 2006, "barcode": "BC002006", "status": "available" } ],
  "format": "ebook",
  "attributes": { "file_type": "EPUB", "file_size_mb": 12, "drm_protected": false },
  "tags": [ "bestseller", "staff-pick" ],
  "reviews": [ { "member_id": 1234, "rating": 4, "comment": "...", "date": "2026-10-01" } ]
}
```

### Relational to document mapping

| PostgreSQL (Portfolio 1) | MongoDB | Design choice |
|---|---|---|
| `books` + `categories` | top-level fields, `category` as a string | Category name copied in (denormalised), so no join |
| `book_authors` + `authors` | embedded `authors` array | The many-to-many junction table disappears |
| `book_copies` | embedded `copies` array | Copies are always viewed with their book, and there are few per book |
| *(no equivalent)* | `attributes` sub-object | Different formats carry different fields without NULL-filled columns |
| *(no equivalent)* | `tags` array, embedded `reviews` | Natural for documents, awkward as extra tables |
| `members`, `loans`, `fines`, `staff` | **stay in PostgreSQL** | See section 5 |

## 4. Operations demonstrated (`mongo_queries.js`)

| Query | Feature |
|---|---|
| Q1 | Exact lookup by ISBN: one read instead of a 4-table join |
| Q2 | Full-text search using a `text` index |
| Q3 | Query on an array field (`tags`) combined with `category` |
| Q4 | Filter on a format-specific nested attribute (`attributes.duration_minutes`) |
| Q5 | `$elemMatch` on an embedded array (books with an available copy) |
| Q6, Q7 | Aggregation pipelines with `$unwind`, `$group`, `$sort` |
| Q8 | **Atomic single-document update**: two attempts to borrow the same copy, the first modifies 1 document and the second modifies 0 |
| Q9 | `explain('executionStats')`: **COLLSCAN before the index, IXSCAN after**, with documents examined falling to roughly the number returned |

Indexes created: unique on `isbn`, compound `category + tags` (multikey because `tags` is an array), `text` on `title`, and `copies.status`.

## 5. Why a document database suits this part of the case study (explain in your own words)

**Good fit (the catalogue):**
- **Read together, stored together.** A catalogue page shows title, authors, copies and reviews at once, so one document read replaces several joins.
- **Variable structure.** Print books, ebooks and audiobooks have different attributes. A document absorbs this without a wide table full of NULLs or one table per format.
- **Arrays are first-class.** Tags, authors and reviews are naturally lists.
- **Horizontal scale.** Documents are self-contained, which makes sharding by `_id` or `category` straightforward (see Portfolio 5).

**Poor fit (loans, fines, members):**
- These are transactional records with strict rules (a copy has one active loan, fines must match returns). They need multi-row ACID transactions, foreign keys and constraints, which PostgreSQL provides more naturally.
- The same loan data is queried in many shapes (per member, per date, overdue), where relational indexes and joins are stronger.

**Trade-offs of the document model:**
- **Duplication.** The category name and author names are copied into each book. Renaming an author means updating many documents.
- **Weaker integrity.** MongoDB does not enforce foreign keys, so a review's `member_id` is not checked against a members collection.
- **Atomicity scope.** Updates to one document are atomic (Q8), but changes across documents need multi-document transactions.
- **Unbounded growth.** An array that grows without limit (for example thousands of reviews) risks the 16 MB document limit. A separate `reviews` collection would then be the better design.

**Polyglot persistence (the recommended architecture):** PostgreSQL stays the system of record for members, loans and fines, while MongoDB serves the read-heavy, flexible catalogue and search.

**Other NoSQL models considered:**

| Model | Possible use at CityLib | Chosen? |
|---|---|---|
| Document (MongoDB) | Catalogue with flexible attributes, reviews | **Yes** |
| Key-value (Redis) | Cache "is copy X available?" or session tokens for the catalogue site | Discussed only |
| Column-family (Cassandra) | Very high-volume event or log streams (for example every catalogue search) | Discussed only |
| Graph (Neo4j) | "Readers who borrowed this also borrowed..." recommendations | Discussed only |

## 6. Technical Reflection (draft, rewrite in your own words)

*Add 3-5 sentences on what you chose to embed and why, which part of the system you deliberately left in PostgreSQL, and what the COLLSCAN to IXSCAN change taught you.*
