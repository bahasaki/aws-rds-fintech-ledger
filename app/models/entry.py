"""
Entry model — the actual debit/credit line of double-entry bookkeeping.

Design choice: a single signed `amount` column (positive = debit, negative
= credit) rather than separate debit/credit columns. This is deliberate:
it makes the core invariant trivial to express and enforce — the sum of
every Entry.amount within one Transaction must equal zero. Separate
debit/credit columns would require a CHECK ensuring exactly one of the two
is non-zero per row, plus a SUM(debit) = SUM(credit) check across the
transaction — more moving parts for the same guarantee. See
docs/adrs/adr-00X-signed-amount-vs-debit-credit-columns.md for the full
tradeoff writeup once written.

Numeric(precision=19, scale=4) avoids float rounding errors entirely —
never use floating point for money.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, ForeignKey, Numeric, DateTime
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from database import Base


class Entry(Base):
    __tablename__ = "entries"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    transaction_id = Column(UUID(as_uuid=True), ForeignKey("transactions.id"), nullable=False)
    account_id = Column(UUID(as_uuid=True), ForeignKey("accounts.id"), nullable=False)

    # Positive = debit, negative = credit. Sum of all entries in a
    # transaction must equal zero — enforced at the application layer
    # in crud/transaction.py, not (yet) as a DB-level constraint.
    amount = Column(Numeric(precision=19, scale=4), nullable=False)

    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    transaction = relationship("Transaction", back_populates="entries")
    account = relationship("Account")
