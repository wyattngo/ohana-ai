"""Async engine + session factory. Reads `DATABASE_URL` from env; no app.config coupling
until Phase 3+. Callers hold `session_factory` (an `async_sessionmaker`) and open a session
per unit of work — never share a session across requests.
"""

from __future__ import annotations

import os

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

_DEFAULT_URL = "postgresql+psycopg://ohana:ohana@localhost:5432/ohana"


def get_database_url() -> str:
    return os.environ.get("DATABASE_URL", _DEFAULT_URL)


def make_engine() -> AsyncEngine:
    return create_async_engine(get_database_url(), echo=False)


def make_session_factory(engine: AsyncEngine | None = None) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(engine or make_engine(), expire_on_commit=False)
