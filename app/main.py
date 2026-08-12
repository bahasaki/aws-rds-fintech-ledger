from fastapi import FastAPI

from config import settings
from routers import accounts, transactions

app = FastAPI(title=settings.app_name)

app.include_router(accounts.router)
app.include_router(transactions.router)


@app.get("/health")
def health():
    """
    Liveness/readiness check. Deliberately does not touch the database —
    a DB-touching health check would fail during a brief connection blip
    and cause unnecessary restarts/alerts for a problem that resolves
    itself. A separate /health/db endpoint would be the right place for
    an actual connectivity check, if one is added later.
    """
    return {"status": "ok"}
