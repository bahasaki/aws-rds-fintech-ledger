# Incident 006: Alembic Migration Failed — ENUM Type Created Twice

**Date:** 2026-08-12
**Severity:** Medium (blocked application deployment; required extensive
live debugging against the running database to isolate)
**Component:** Alembic migration / SQLAlchemy PostgreSQL ENUM handling

## Symptoms

After fixing Incident 005 (wrong `Base` import in `alembic/env.py`),
`alembic upgrade head` progressed further but failed with:

```
sqlalchemy.exc.ProgrammingError: (psycopg2.errors.DuplicateObject) type
"account_type" already exists

[SQL: CREATE TYPE account_type AS ENUM ('asset', 'liability', 'equity',
'revenue', 'expense')]
```

This was confusing because direct queries against the database
(`SELECT typname FROM pg_type WHERE typname = 'account_type'`) both
before and after the failed migration attempt returned zero rows — the
type did not exist, was not left behind by a previous attempt, and there
was no other process or connection touching the database
(`pg_stat_activity` showed only the diagnostic query itself).

## Investigation

The dead ends ruled out, in order:
1. **Stale ENUM from an earlier partial run** — ruled out; `pg_type`
   showed zero rows immediately before the failing command.
2. **A second process racing the migration** — ruled out; `systemctl
   status ledger-app` showed the unit didn't even exist yet (bootstrap
   had failed before reaching that step), and no other alembic/cloud-init
   processes were running.
3. **A zombie transaction holding an uncommitted CREATE TYPE** — ruled
   out; `pg_stat_activity` showed only one active connection, the
   diagnostic query itself.

With external causes eliminated, the remaining candidate was the
migration file's own logic. Re-reading
`alembic/versions/772957eac988_initial_ledger_schema.py` line by line
against the traceback showed the failing call originated from
`sqlalchemy/dialects/postgresql/named_types.py`'s `_on_table_create`
event handler — not from the migration's own explicit
`account_type.create(op.get_bind())` call. This handler fires
automatically whenever a table is created with an ENUM-typed column,
attempting to create the ENUM type as a side effect of `create_table`.

## Root Cause

The migration created the `account_type` ENUM **twice**, once
implicitly and once explicitly, within the same `upgrade()` call:

1. `account_type.create(op.get_bind())` — an explicit, direct call that
   creates the type.
2. `op.create_table("accounts", ..., sa.Column("account_type",
   account_type, ...))` — passing the *same* ENUM object as a column
   type triggers SQLAlchemy's automatic `before_create` DDL event, which
   independently attempts to create that ENUM again, because the object
   instance has no signal telling it the type was already created
   elsewhere.

Step 2's automatic creation attempt is what failed with
`DuplicateObject`, immediately after step 1 had just succeeded within
the same transaction — which is also why external diagnostic queries run
*after* the whole migration failed and rolled back saw zero rows: the
successful `CREATE TYPE` from step 1 was rolled back along with
everything else once step 2 raised.

## Fix

Used a second `postgresql.ENUM(...)` instance with `create_type=False`
specifically for the column definition, so SQLAlchemy's automatic DDL
event is told not to attempt creation — creation is the explicit call's
job alone:

```python
account_type = postgresql.ENUM(..., name="account_type")
account_type.create(op.get_bind())

account_type_in_table = postgresql.ENUM(
    ..., name="account_type", create_type=False,
)

op.create_table(
    "accounts",
    ...,
    sa.Column("account_type", account_type_in_table, nullable=False),
    ...,
)
```

## Verification

After the fix, `alembic upgrade head` needs to be re-run end to end
against a clean database (this incident's database state was rolled
back automatically by the failed transaction, so no manual cleanup of
the partially-created ENUM was required — the transaction rollback
handled that).

## Prevention

- When a PostgreSQL ENUM type needs to be created explicitly ahead of a
  table (e.g. to control ordering, or reuse across multiple tables),
  every subsequent reference to that type in a column definition within
  the same migration must use `create_type=False` on that ENUM instance.
  The explicit `.create()` call and the type-safe column reference are
  two separate concerns and both need to agree on who is responsible for
  creation.
- The `downgrade()` function's own `account_type.drop(op.get_bind())`
  does not have an equivalent double-drop risk (dropping is not
  triggered automatically by `drop_table`), so no analogous fix was
  needed there.

## Lessons Learned

This is the first incident in this project where the root cause was in
**our own application-level migration code**, rather than an AWS API
constraint, an account-tier restriction, or a shell-parsing mismatch
(Incidents 001–005). The debugging path here also illustrates a useful
technique: when a database error is reported but direct queries against
that same database contradict it (type doesn't exist, no other
connections), the most likely explanation is that the failing statement
is inside a transaction that gets rolled back — so what actually
happened has to be reconstructed from the traceback's call stack rather
than from the database's post-failure state, which will have already
reverted.
