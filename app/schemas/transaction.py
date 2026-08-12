import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, field_validator


class EntryCreate(BaseModel):
    account_id: uuid.UUID
    amount: Decimal  # positive = debit, negative = credit


class EntryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    account_id: uuid.UUID
    amount: Decimal
    created_at: datetime


class TransactionCreate(BaseModel):
    description: str
    entries: list[EntryCreate]

    @field_validator("entries")
    @classmethod
    def entries_must_balance(cls, entries: list[EntryCreate]) -> list[EntryCreate]:
        # Core double-entry invariant, enforced at the API boundary
        # before anything reaches the database: every transaction's
        # entries must sum to exactly zero (debits == credits).
        if len(entries) < 2:
            raise ValueError("A transaction requires at least two entries")
        total = sum(e.amount for e in entries)
        if total != 0:
            raise ValueError(f"Entries must sum to zero, got {total}")
        return entries


class TransactionRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    description: str
    created_at: datetime
    entries: list[EntryRead]
