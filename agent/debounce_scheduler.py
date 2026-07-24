"""Turn quiet conversations into parked AI drafts."""

from __future__ import annotations

from collections.abc import Mapping
from datetime import UTC, datetime

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from agent.orchestrator import Drafter, receive_and_draft
from channels.base import OutboundChannel
from db.repos import DebounceRepo, MessageRepo


class DebounceScheduler:
    def __init__(
        self,
        session_factory: async_sessionmaker[AsyncSession],
        drafter: Drafter,
        channels: Mapping[str, OutboundChannel],
    ) -> None:
        self._session_factory = session_factory
        self._drafter = drafter
        self._channels = channels

    async def run_once(self, *, limit: int = 100) -> int:
        async with self._session_factory() as session:
            conversations = await DebounceRepo(session).claim_due(
                now=datetime.now(UTC), limit=limit
            )

        drafted = 0
        for conversation in conversations:
            channel = self._channels.get(conversation.channel)
            if channel is None:
                continue
            async with self._session_factory() as session:
                history = await MessageRepo(session, shop_scope=conversation.shop_id).last_n(
                    conversation.id, limit=1
                )
            if not history:
                continue
            await receive_and_draft(
                shop_id=conversation.shop_id,
                customer_id=conversation.customer_id,
                conversation_id=conversation.id,
                message=history[-1].content,
                drafter=self._drafter,
                sender=channel,  # type: ignore[arg-type]
                session_factory=self._session_factory,
                shop_auto_enabled_intents=frozenset(),
            )
            drafted += 1
        return drafted
