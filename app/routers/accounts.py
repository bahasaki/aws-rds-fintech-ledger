import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from schemas.account import AccountCreate, AccountRead
import crud.account as crud

router = APIRouter(prefix="/accounts", tags=["accounts"])


@router.post("", response_model=AccountRead, status_code=201)
def create_account(account_in: AccountCreate, db: Session = Depends(get_db)):
    return crud.create_account(db, account_in)


@router.get("", response_model=list[AccountRead])
def list_accounts(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    return crud.list_accounts(db, skip=skip, limit=limit)


@router.get("/{account_id}", response_model=AccountRead)
def get_account(account_id: uuid.UUID, db: Session = Depends(get_db)):
    account = crud.get_account(db, account_id)
    if account is None:
        raise HTTPException(status_code=404, detail="Account not found")
    return account
