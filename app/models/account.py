"""
Account model.

account_type follows standard accounting categories. This isn't just
labeling — it's what lets the application (or a future report) reason
about normal balance direction: assets/expenses normally carry a debit
balance, liabilities/equity/revenue normally carry a credit balance.
"""

import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, DateTime, Enum as SAEnum
from sqlalchemy.dialects.postgresql import UUID

from database import Base


class AccountType(str, enum.Enum):
    asset = "asset"
    liability = "liability"
    equity = "equity"
    revenue = "revenue"
    expense = "expense"


class Account(Base):
    __tablename__ = "accounts"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String, nullable=False)
    account_type = Column(SAEnum(AccountType, name="account_type"), nullable=False)
    currency = Column(String(3), nullable=False, default="USD")
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
