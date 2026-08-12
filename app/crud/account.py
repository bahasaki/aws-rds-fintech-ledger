import uuid

from sqlalchemy.orm import Session

from models.account import Account
from schemas.account import AccountCreate


def create_account(db: Session, account_in: AccountCreate) -> Account:
    account = Account(
        name=account_in.name,
        account_type=account_in.account_type,
        currency=account_in.currency,
    )
    db.add(account)
    db.commit()
    db.refresh(account)
    return account


def get_account(db: Session, account_id: uuid.UUID) -> Account | None:
    return db.query(Account).filter(Account.id == account_id).first()


def list_accounts(db: Session, skip: int = 0, limit: int = 100) -> list[Account]:
    return db.query(Account).offset(skip).limit(limit).all()
