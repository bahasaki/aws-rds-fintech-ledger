# ADR 004: Single Signed `amount` Column Instead of Separate Debit/Credit Columns

## Context

The `entries` table (`app/models/entry.py`) is the core of the
double-entry bookkeeping model. Every entry needs to represent either a
debit or a credit against an account, and the fundamental invariant of
double-entry accounting — every transaction's debits equal its credits
— needs to be checkable in a straightforward way.

Two common schema designs exist for this in real accounting systems:
a single signed amount column, or two separate non-negative columns
(`debit_amount` and `credit_amount`, exactly one of which is non-zero
per row).

## Decision

Use a single `Numeric(19, 4)` column named `amount`, where a positive
value represents a debit and a negative value represents a credit.

## Alternatives considered

**Separate `debit` and `credit` columns.** This is the more traditional
accounting-software schema, and it has a real advantage: it's harder to
accidentally introduce a sign error, because there's no sign to get
wrong — a debit is stored as a positive number in the `debit` column,
full stop. It also matches how a general ledger report is often
displayed (debit and credit as separate columns). The cost: enforcing
"exactly one of the two is non-zero per row" requires a `CHECK`
constraint (`(debit = 0) != (credit = 0)` or similar), and the zero-sum
invariant across a transaction becomes `SUM(debit) = SUM(credit)`
grouped by transaction, rather than a simple `SUM(amount) = 0`.

**Single signed `amount` column (chosen).** The zero-sum invariant
becomes literally `SUM(amount) = 0` — this is what
`schemas/transaction.py`'s Pydantic validator checks directly, with no
grouping or comparison between two separate sums needed. There's one
fewer column, one fewer constraint to write, and one fewer way for the
two values to disagree with each other. The tradeoff is that a sign
error (recording a debit as negative by mistake) produces a
syntactically valid row that silently breaks the accounting semantics —
there's no schema-level guard against that specific mistake the way
"which column has the non-zero value" naturally provides.

## Consequences

- The zero-sum check lives entirely in the API layer
  (`schemas/transaction.py`'s `entries_must_balance` validator), not as
  a database-level `CHECK` constraint. PostgreSQL `CHECK` constraints
  can't natively aggregate across multiple rows of the same table, so
  enforcing this at the database level would require a trigger — not
  used in this project's initial schema, tracked as a possible future
  hardening step rather than implemented from the start.
- Any code that inserts directly into the `entries` table without going
  through the API (e.g. a future data migration or bulk-import script)
  bypasses the zero-sum check entirely, since it's application-level,
  not database-level. This is an accepted risk for the current scope of
  the project; a production system handling real money would likely
  want the trigger-based database constraint as defense in depth, not
  reliance on the API layer alone.
- Reporting queries that want a traditional "debit / credit" columnar
  view (e.g. a general ledger report) would need to derive it with a
  `CASE WHEN amount > 0 THEN amount ELSE 0 END` style expression at
  query time, rather than reading two columns directly. No such
  reporting feature exists yet in this project, so this cost hasn't
  been incurred in practice — but it's the concrete price of this
  choice if that feature were added later.
