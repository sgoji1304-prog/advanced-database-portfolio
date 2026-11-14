# Portfolio 3: Transactions and Concurrency

Case study: **CityLib Public Library**. Database: PostgreSQL (default isolation level: READ COMMITTED).

## 1. Files

| File | What it demonstrates |
|---|---|
| `01_functions.sql` | `borrow_book()` and `return_book()` as atomic business transactions, using row locks |
| `02_commit_rollback.sql` | COMMIT, ROLLBACK, atomicity on failure, SAVEPOINT, a late return with a fine |
| `lost_update_demo.sh` | A real **lost update** between two staff members, plus three fixes |
| `isolation_demo.sh` | **Non-repeatable read** under READ COMMITTED versus REPEATABLE READ |
| `deadlock_demo.sh` | A **deadlock** detected and resolved by PostgreSQL |

## 2. How to run

```bash
psql -d citylib -f 01_functions.sql
psql -d citylib -f 02_commit_rollback.sql      # no ON_ERROR_STOP: some statements are meant to fail
chmod +x *.sh
./lost_update_demo.sh unsafe                    # the bug
./lost_update_demo.sh for_update                # fix 1
./lost_update_demo.sh atomic                    # fix 2
./lost_update_demo.sh repeatable_read           # fix 3
./isolation_demo.sh read_committed
./isolation_demo.sh repeatable_read
./deadlock_demo.sh
```

The `.sh` scripts need a Bash shell (Git Bash or WSL on Windows). Set `PGHOST`, `PGUSER` and `PGPASSWORD` if your connection needs them, and `DB=yourdbname` if it is not `citylib`. Each script opens **two** psql sessions at once and uses `pg_sleep` to force the exact interleaving, so the problem is reproducible every time.

**Screenshot each command's output** as evidence and save them in `screenshots/`.

## 3. Commit, rollback and atomicity (`02_commit_rollback.sql`)

| Demo | What it shows | Expected result |
|---|---|---|
| 1 | `BEGIN; borrow_book(); COMMIT;` | Loan created and copy marked `on_loan`, visible to everyone after COMMIT |
| 2 | Update then `ROLLBACK` | Copy status returns to `available`, as if nothing happened |
| 3 | One statement succeeds, the next violates the one-active-loan rule | Error, then `ROLLBACK`. The first statement is undone too (**atomicity**) |
| 4 | `borrow_book()` on an unavailable copy | Function raises an exception, nothing is written |
| 5 | `SAVEPOINT` / `ROLLBACK TO SAVEPOINT` | Only the failed part is undone, the first loan survives |
| 6 | `return_book()` on time, then 10 days late | Fine is 0, then 500.00 (10 days x 50). Loan, copy and fine change together |

## 4. Concurrency problem and control mechanisms

### 4.1 Lost update (`lost_update_demo.sh`)

Fine #1 is 500. Staff A waives 100. Staff B adds a 50 surcharge. **Correct final amount: 450.**

| Mode | How it works | Final amount | Outcome |
|---|---|---|---|
| `unsafe` | Both read 500 in READ COMMITTED, compute a new value in the application, and write it back | **550** | **A's waiver is silently lost** |
| `for_update` | `SELECT ... FOR UPDATE` locks the row, so B waits and then reads 400 | 450 | Correct (pessimistic locking) |
| `atomic` | `SET amount = amount - 100` / `amount + 50` computed inside the database | 450 | Correct (no read-modify-write gap) |
| `repeatable_read` | B's update fails with *could not serialize access due to concurrent update* | 400 | Correct and safe: the database refuses the stale write, and the application must **retry** B |

### 4.2 Isolation levels (`isolation_demo.sh`)

| Level | A's first read | A's second read (after B commits a change) | Phenomenon |
|---|---|---|---|
| READ COMMITTED | available | **damaged** | **Non-repeatable read** |
| REPEATABLE READ | available | available | Prevented (A works from a snapshot) |

### 4.3 Locking in `borrow_book()`

- `FOR UPDATE` on the **copy** row: two people trying to borrow the *last copy* queue up, and the second one sees `on_loan` and is refused.
- `FOR UPDATE` on the **member** row: two simultaneous borrows by the *same* member are serialised, so the 5-loan limit cannot be bypassed by a race (a check-then-insert race).
- The partial unique index from Portfolio 1 is the last line of defence: even without locking, the database refuses a second active loan for the same copy.

### 4.4 Deadlock (`deadlock_demo.sh`)

A locks copy 701 then wants 702, while B locks 702 then wants 701. PostgreSQL reports `deadlock detected`, aborts one session and lets the other commit. **Prevention:** always lock rows in a consistent order (for example ascending `copy_id`) and keep transactions short.

## 5. ACID summary (write this in your own words)

- **Atomicity:** demos 3, 4, 5.
- **Consistency:** CHECK, FOREIGN KEY and the partial unique index reject invalid states, so a transaction cannot leave the database in a broken state.
- **Isolation:** the lost-update and isolation-level demos.
- **Durability:** once COMMIT returns, the change survives a crash because PostgreSQL writes it to the write-ahead log first.

## 6. Technical Reflection (draft, rewrite in your own words)

*Add 3-5 sentences about which fix you would choose in production for the lost update and why (for example, the atomic update is simplest and fastest, `FOR UPDATE` suits multi-step logic, REPEATABLE READ needs retry logic), and what surprised you when you ran the unsafe version.*
