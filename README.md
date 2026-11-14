# MIT 8103 Advanced Database Systems: Practical Portfolio

**Selected organisation:** CityLib Public Library (a simulated municipal library management system)

| Item | Description |
|---|---|
| Nature of the system | Cataloguing books, lending physical copies to members, tracking returns, charging fines for late returns |
| Users of the database | Members, librarians and assistants, administrators |
| Major data stored | Books, authors, categories, copies, members, staff, loans, fines |
| Key operations | Search the catalogue, borrow, return, calculate fines, list overdue loans, report most-borrowed books |

**Technology:** PostgreSQL (relational) and MongoDB (document). All five portfolios use this same case study.

## Repository structure

| Folder | Portfolio | Contents |
|---|---|---|
| [`portfolio-1-database-design/`](portfolio-1-database-design) | Database Design and Modelling | ER diagram, schema, constraints, seed data, normalisation |
| [`portfolio-2-query-optimisation/`](portfolio-2-query-optimisation) | Query Processing and Optimisation | 5 queries, execution plans, indexes, materialised view, analysis |
| [`portfolio-3-transactions-concurrency/`](portfolio-3-transactions-concurrency) | Transactions and Concurrency | Commit/rollback, lost update and fixes, isolation levels, deadlock |
| [`portfolio-4-nosql/`](portfolio-4-nosql) | NoSQL and Advanced Data Models | MongoDB document model, queries, aggregation, indexes |
| [`portfolio-5-distributed-cloud/`](portfolio-5-distributed-cloud) | Distributed and Cloud Database | Partitioning/sharding, replication, failover, cloud design |
| [`docs/`](docs) | Final documentation | AI-use declaration, LMS summary, verification notes |

Each folder has its own `README.md` explaining how the work was implemented and tested.

## Quick start

```bash
createdb citylib
psql -d citylib -f portfolio-1-database-design/schema.sql
psql -d citylib -f portfolio-1-database-design/seed.sql
# then follow each portfolio's README
```

Requirements: PostgreSQL 14 or newer, MongoDB 6 or newer with `mongosh`, and Bash (Linux, macOS or WSL) for the `.sh` demos.

## AI use

AI assistance was used in this project. See [`docs/AI_USE_DECLARATION.md`](docs/AI_USE_DECLARATION.md).
