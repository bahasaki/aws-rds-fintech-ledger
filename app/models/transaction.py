"""
Transaction model.

A Transaction is deliberately "thin" — it has no amount or account of its
own. It exists purely as a grouping container for its Entry rows, which is
what makes double-entry bookkeeping possible: the balance-sums-to-zero
invariant is checked across all Entries belonging to one Transaction, not
on the Transaction itself.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from database import Base


class Transaction(Base):
    __tablename__ = "transactions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    description = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    entries = relationship("Entry", back_populates="transaction", cascade="all, delete-orphan")
