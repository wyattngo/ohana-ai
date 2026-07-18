"""Shop-scoped repositories — the ONLY sanctioned access path for tenant-scoped tables.

Every method takes a scope in the constructor (`shop_scope: str`) and every SELECT/UPDATE
statement threads it into a `WHERE shop_id = :scope` clause SQL-level. A caller cannot
build a repo without picking a shop, and one repo instance can only ever surface / mutate
rows for that shop. Ad-hoc `session.execute(select(PendingReply)…)` outside these repos is
a S4 breach.

Currently only `PendingReplyRepo` lives here. Message / Embedding stay in-place at the
retrieval and orchestrator boundaries because those paths already lock shop scope in a
different layer (retrieval/pgvector.py's `PgvectorRetriever(shop_scope=…)` for embeddings,
orchestrator direct-insert with a verified shop_id for messages). If Message ever grows a
read-by-shop use case, its repo lives here too.
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import UTC, datetime
from typing import Any, cast

from sqlalchemy import select, update
from sqlalchemy.engine import CursorResult
from sqlalchemy.ext.asyncio import AsyncSession

from db.models import Conversation, PendingReply


class ConversationRepo:
    """Shop-scoped access to `conversations` (spec 06 Phase F0).

    Same seam as PendingReplyRepo: scope is chosen at construction, every statement carries
    `WHERE shop_id = :scope`. Note this is belt-AND-braces with the composite FKs in
    db/models.py — the FKs stop a row from being WRITTEN across shops, this repo stops rows
    from being READ across shops. Neither replaces the other.
    """

    def __init__(self, session: AsyncSession, *, shop_scope: str) -> None:
        if not shop_scope:
            raise ValueError("shop_scope is required — no default, no cross-tenant surface")
        self._session = session
        self._shop_scope = shop_scope

    async def list_recent(self, *, limit: int = 50) -> Sequence[Conversation]:
        """Most-recent-first threads for THIS shop."""
        stmt = (
            select(Conversation)
            .where(Conversation.shop_id == self._shop_scope)
            .order_by(Conversation.created_at.desc())
            .limit(limit)
        )
        return (await self._session.execute(stmt)).scalars().all()

    async def get(self, conversation_id: str) -> Conversation | None:
        """Fetch one thread by id — scoped. An id owned by another shop returns None
        (same shape as "not found"; we do not distinguish, so the caller cannot probe
        for existence of another shop's rows)."""
        stmt = (
            select(Conversation)
            .where(Conversation.shop_id == self._shop_scope)
            .where(Conversation.id == conversation_id)
        )
        return (await self._session.execute(stmt)).scalar_one_or_none()


class PendingReplyRepo:
    def __init__(self, session: AsyncSession, *, shop_scope: str) -> None:
        if not shop_scope:
            raise ValueError("shop_scope is required — no default, no cross-tenant surface")
        self._session = session
        self._shop_scope = shop_scope

    async def create(
        self,
        *,
        reply_id: str,
        conversation_id: str,
        customer_id: str,
        draft_text: str,
        intent: str,
        confidence: float,
    ) -> PendingReply:
        """Insert a new parked draft. `shop_id` is baked from the repo scope — the caller
        does NOT pass it, so a compromised caller cannot cause a row to land under a shop
        other than the one this repo was scoped to."""
        row = PendingReply(
            reply_id=reply_id,
            shop_id=self._shop_scope,
            conversation_id=conversation_id,
            customer_id=customer_id,
            draft_text=draft_text,
            intent=intent,
            confidence=confidence,
            status="pending",
        )
        self._session.add(row)
        await self._session.commit()
        return row

    async def list_pending(self) -> Sequence[PendingReply]:
        """List parked drafts for THIS shop, oldest-first (fair queue for the seller)."""
        stmt = (
            select(PendingReply)
            .where(PendingReply.shop_id == self._shop_scope)
            .where(PendingReply.status == "pending")
            .order_by(PendingReply.created_at)
        )
        return (await self._session.execute(stmt)).scalars().all()

    async def get(self, reply_id: str) -> PendingReply | None:
        """Fetch one parked draft by id — scoped. A reply_id belonging to another shop
        returns None (not a leak, not a raise — same shape as "row not found")."""
        stmt = (
            select(PendingReply)
            .where(PendingReply.shop_id == self._shop_scope)
            .where(PendingReply.reply_id == reply_id)
        )
        return (await self._session.execute(stmt)).scalar_one_or_none()

    async def mark_decided(self, reply_id: str, *, new_status: str, decided_by: str) -> int:
        """Transition a parked reply to approved / rejected / sent. Returns the number of
        rows updated — 0 means the reply_id doesn't exist FOR THIS SHOP (either wrong
        shop, or already-decided). The `shop_id` clause is the S4 ownership seam: a shop_b
        seller cannot approve a shop_a draft even if they somehow know the reply_id."""
        if new_status not in {"approved", "rejected", "sent"}:
            raise ValueError(f"invalid status transition: {new_status!r}")
        stmt = (
            update(PendingReply)
            .where(PendingReply.shop_id == self._shop_scope)
            .where(PendingReply.reply_id == reply_id)
            .where(PendingReply.status.in_(["pending", "approved"]))
            .values(
                status=new_status,
                decided_by=decided_by,
                decided_at=datetime.now(UTC),
            )
        )
        # `AsyncSession.execute` is typed as returning `Result`, but a DML statement always
        # yields a `CursorResult` — that is the only variant carrying `rowcount`, and the
        # rowcount is what tells the caller whether the reply belonged to THIS shop.
        result = cast("CursorResult[Any]", await self._session.execute(stmt))
        await self._session.commit()
        return int(result.rowcount or 0)
