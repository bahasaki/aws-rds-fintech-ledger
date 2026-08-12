"""
Alembic environment.

Two deliberate choices here:
1. target_metadata points at our models' Base.metadata, so
   `alembic revision --autogenerate` can diff the DB against the actual
   SQLAlchemy models instead of requiring every column to be hand-written.
2. The DB URL comes from config.settings (the same Pydantic settings the
   running app uses), not a separate hardcoded value in alembic.ini —
   there is exactly one source of truth for how to reach the database.
"""

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from config import settings
from models import Base  # noqa: F401 — populates Base.metadata via models/__init__.py

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata

# Override whatever (blank) sqlalchemy.url is in alembic.ini with the
# real one from application settings.
config.set_main_option("sqlalchemy.url", settings.database_url)


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
