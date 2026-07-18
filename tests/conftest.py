"""Shared test fixtures (spec 06 Phase F2 — closes ISSUE-014).

Before this file, every DB test hand-rolled the same six lines: build an async engine, drop
every table, recreate them, wrap a sessionmaker, and remember to dispose at the end. That
duplication is what ISSUE-014 tracked — not an aesthetic complaint: each copy was a place
where someone could forget the dispose (leaked connections) or the drop (a test seeing the
previous test's rows and passing for the wrong reason).

Deliberately NOT done here: mass-refactoring the pre-existing tests onto these fixtures.
`test_inbox_ui_e2e.py` in particular manages its own engine because it also owns a targeted
row-cleanup fixture tied to a SHARED tenant id; rewriting green tests purely for tidiness
risks changing what they assert, and spec 06 §12 forbids that trade. New tests use `fresh_db`;
old tests get migrated only when they're being touched for another reason.
"""

from __future__ import annotations

import os
from collections.abc import AsyncIterator, Awaitable, Callable

import pytest
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql+psycopg://ohana:ohana@localhost:5432/ohana"
)

_FreshDb = Callable[[], Awaitable[tuple[AsyncEngine, async_sessionmaker[AsyncSession]]]]


@pytest.fixture
async def fresh_db() -> AsyncIterator[_FreshDb]:
    """Yield a factory that hands back `(engine, session_factory)` over a CLEAN schema.

    Clean means every table in `Base.metadata` is dropped and recreated, so a test can never
    pass because of a row another test left behind. Engines are disposed on teardown even if
    the test raises — the old hand-rolled `await engine.dispose()` at the end of each test
    was skipped entirely whenever an assertion failed mid-test, leaking a pool per failure.

    Schema comes from `Base.metadata.create_all`, NOT from Alembic. That is intentional for
    speed, and it means these fixtures do NOT prove the migrations are correct — migration
    correctness has its own gate (`alembic upgrade head && downgrade -1 && upgrade head` in
    spec 06 F0's GATE_FULL). Do not conflate the two.
    """
    from db.models import Base

    created: list[AsyncEngine] = []

    async def _make() -> tuple[AsyncEngine, async_sessionmaker[AsyncSession]]:
        engine = create_async_engine(DATABASE_URL, echo=False)
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
            await conn.run_sync(Base.metadata.create_all)
        created.append(engine)
        return engine, async_sessionmaker(engine, expire_on_commit=False)

    yield _make

    for engine in created:
        await engine.dispose()
