"""
Database engine and session setup.

pool_pre_ping=True is deliberate: RDS connections can go stale (e.g.
after a failover, or the connection simply idling past a timeout), and
without pre-ping, the first query on a stale connection fails outright
instead of transparently reconnecting.
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

from config import settings

engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    """FastAPI dependency — yields a session, always closes it after the request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
