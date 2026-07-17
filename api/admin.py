"""Admin ingest endpoints (F1 — wiki corpus loader).

GĐ0 accepts raw text via JSON; a docx/pdf upload path can wrap `parsing.extract.extract_text`
in a later phase. This endpoint WAS unauthenticated at GĐ0 (Phase 3+ was to require an admin
JWT) — spec 04 Phase P2 is that gate: `require_admin` below, mounted together in
`app/main.py` (never one without the other — see that module's docstring).
"""

from __future__ import annotations

import os
from typing import Protocol

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from auth.identity import Identity
from parsing.ingest import PLATFORM_SHOP_ID, ingest_wiki

_DEV_EMBED_DIM = 1536  # must match db.models.Embedding.embedding (Vector(_EMBED_DIM))


class _EmbedderProto(Protocol):
    async def embed(self, texts: list[str]) -> list[list[float]]: ...


class _DeterministicDevEmbedder:
    """GD0.5 placeholder embedder — the live default `app/main.py` wires via `default_embedder()`
    below, NOT a test-only fixture.

    `agent/providers/openai_embedder.py` already has a real `OpenAIEmbedder`, but its
    `__init__` unconditionally calls `app.config.get_settings()` — a module that does not
    exist anywhere in this repo (verified: no `app/config.py` on disk or in git history). It
    is dead/orphaned code carried over from the drnickv4 port and was never wired into
    `app/main.py`. There is also no `OPENAI_API_KEY` configured in this dev environment.
    Wiring the real embedder here would crash `app/main.py` at import time — taking down the
    already-shipped P0/P1 screens along with it — for a phase whose actual scope is the admin
    AUTH guard, not the embedding pipeline.

    Deterministic hash-based vectors, same shape `tests/test_wiki_rag.py`'s `FakeEmbedder`
    already uses to gate the ingest/search round-trip without a network call. This exercises
    the real storage/HTTP contract (chunk count, DB rows) for real; it is NOT representative
    of real semantic search quality. Swap for
    `agent.providers.openai_embedder.OpenAIEmbedder` once `app/config.py` exists and PRE-003
    backfill lands real wiki content — flagged in the P2 ANCHOR report, not left silently as
    the permanent embedder.

    Refuses to run outside dev (see `embed`). A docstring saying "placeholder" does not make a
    placeholder safe — the same reasoning that gated `auth.identity.get_jwt_secret`'s dev
    fallback on `OHANA_ENV` applies here.
    """

    async def embed(self, texts: list[str]) -> list[list[float]]:
        # Fail LOUD outside dev rather than returning hash vectors that look like embeddings.
        # The failure mode this closes is silent-wrong, not crash: ingest would answer
        # {"success": true, "chunks": N} while writing semantically meaningless vectors, so
        # `search_wiki` would then feed near-random chunks to the drafter and the AI would
        # answer a customer confidently from the wrong source. Nobody sees a stack trace; they
        # see a plausible wrong reply. Raising here keeps `app/main.py` importable (P0/P1
        # screens stay up) and confines the blast radius to this one route.
        if os.environ.get("OHANA_ENV") != "dev":
            raise RuntimeError(
                "Wiki ingest is unavailable: no real embedder is configured "
                "(agent/providers/openai_embedder.py needs app/config.py, which does not exist). "
                "Refusing to write placeholder vectors outside dev — they would silently "
                "corrupt wiki-RAG answers."
            )
        out: list[list[float]] = []
        for t in texts:
            vec = [0.0] * _DEV_EMBED_DIM
            for tok in t.lower().split():
                vec[hash(tok) % _DEV_EMBED_DIM] = 1.0
            out.append(vec)
        return out


def default_embedder() -> _EmbedderProto:
    """Factory `app/main.py` calls at wiring time — see `_DeterministicDevEmbedder` docstring
    for why this isn't the real OpenAI embedder yet."""
    return _DeterministicDevEmbedder()


class WikiIngestRequest(BaseModel):
    text: str = Field(..., min_length=1)
    source_ref: str = Field(..., min_length=1)
    shop_id: str = Field(default=PLATFORM_SHOP_ID)


class WikiIngestResponse(BaseModel):
    success: bool
    chunks: int


def build_router(
    embedder: _EmbedderProto,
    session_factory: async_sessionmaker[AsyncSession],
    admin_dep: object,  # dependency → Identity; 403s non-admin (auth.identity.require_admin)
) -> APIRouter:
    router = APIRouter(prefix="/admin", tags=["admin"])

    @router.post("/wiki/ingest", response_model=WikiIngestResponse)
    async def wiki_ingest(
        req: WikiIngestRequest,
        _admin: Identity = Depends(admin_dep),  # type: ignore[valid-type]
    ) -> WikiIngestResponse:
        n = await ingest_wiki(
            session_factory,
            embedder,
            text=req.text,
            source_ref=req.source_ref,
            shop_id=req.shop_id,
        )
        return WikiIngestResponse(success=True, chunks=n)

    return router
