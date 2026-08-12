import uuid

from sqlalchemy.orm import Session, joinedload

from models.account import Account
from models.transaction import Transaction
from models.entry import Entry
from schemas.transaction import TransactionCreate


class AccountNotFoundError(Exception):
    """Raised when a transaction references an account_id that doesn't exist."""


def create_transaction(db: Session, tx_in: TransactionCreate) -> Transaction:
    # The zero-sum invariant is already checked by the Pydantic schema
    # validator (schemas/transaction.py) before this function is ever
    # called. This function's remaining responsibility is checking that
    # every referenced account actually exists, then persisting
    # everything atomically in one transaction.
    account_ids = {e.account_id for e in tx_in.entries}
    existing_ids = {
        a.id for a in db.query(Account.id).filter(Account.id.in_(account_ids)).all()
    }
    missing = account_ids - existing_ids
    if missing:
        raise AccountNotFoundError(f"Account(s) not found: {missing}")

    transaction = Transaction(description=tx_in.description)
    db.add(transaction)

    for entry_in in tx_in.entries:
        entry = Entry(
            transaction=transaction,
            account_id=entry_in.account_id,
            amount=entry_in.amount,
        )
        db.add(entry)

    db.commit()
    db.refresh(transaction)
    return transaction


def get_transaction(db: Session, transaction_id: uuid.UUID) -> Transaction | None:
    return (
        db.query(Transaction)
        .options(joinedload(Transaction.entries))
        .filter(Transaction.id == transaction_id)
        .first()
    )


def list_transactions(db: Session, skip: int = 0, limit: int = 100) -> list[Transaction]:
    return (
        db.query(Transaction)
        .options(joinedload(Transaction.entries))
        .order_by(Transaction.created_at.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )
