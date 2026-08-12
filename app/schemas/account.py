import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict

from models.account import AccountType


class AccountCreate(BaseModel):
    name: str
    account_type: AccountType
    currency: str = "USD"


class AccountRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    account_type: AccountType
    currency: str
    created_at: datetime
