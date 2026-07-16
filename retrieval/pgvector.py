"""pgvector-backed Retriever. The ONLY place that raw-queries the `embeddings` table."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from db.models import Embedding
from retrieval.base import Hit, Retriever


class PgvectorRetriever(Retriever):
    def __init__(self, sm: async_sessionmaker[AsyncSession]) -> None:
        self._sm = sm

    async def search(self, namespaces: list[str], query: list[float], k: int) -> list[Hit]:
        if not namespaces:  # no scope → no results (never "all")
            return []
        # SQL-level namespace filter applied BEFORE order/limit → out-of-namespace rows can NEVER
        # surface even if globally nearer (this is what distinguishes it from leaky post-filtering).
        dist = Embedding.embedding.cosine_distance(query).label("dist")
        stmt = (
            select(Embedding.namespace, Embedding.source_ref, Embedding.chunk, dist)
            .where(Embedding.namespace.in_(namespaces))
            # Drained / not-yet-indexed rows (NULL embedding) have no usable vector — exclude them
            # so they never surface and `cosine_distance` never yields NULL. Guards any
            # partial-reindex window (e.g. drain-then-reembed migrations).
            .where(Embedding.embedding.is_not(None))
            .order_by(dist)
            .limit(k)
        )
        async with self._sm() as session:
            rows = (await session.execute(stmt)).all()
        return [Hit(namespace=r[0], source_ref=r[1], chunk=r[2], score=float(r[3])) for r in rows]
