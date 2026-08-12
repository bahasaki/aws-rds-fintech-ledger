"""
Import every model here so that Base.metadata is fully populated
when Alembic's env.py imports this package for autogenerate.
"""

from models.account import Account, AccountType  # noqa: F401
from models.transaction import Transaction  # noqa: F401
from models.entry import Entry  # noqa: F401
