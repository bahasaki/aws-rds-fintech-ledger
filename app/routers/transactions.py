import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from schemas.transaction import TransactionCreate, TransactionRead
import crud.transaction as crud

router = APIRouter(prefix="/transactions", tags=["transactions"])


@router.post("", response_model=TransactionRead, status_code=201)
def create_transaction(tx_in: TransactionCreate, db: Session = Depends(get_db)):
    try:
        return crud.create_transaction(db, tx_in)
    except crud.AccountNotFoundError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("", response_model=list[TransactionRead])
def list_transactions(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    return crud.list_transactions(db, skip=skip, limit=limit)


@router.get("/{transaction_id}", response_model=TransactionRead)
def get_transaction(transaction_id: uuid.UUID, db: Session = Depends(get_db)):
    transaction = crud.get_transaction(db, transaction_id)
    if transaction is None:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return transaction
