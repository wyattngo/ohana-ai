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

from agent.providers.openai_embedder import OpenAIEmbedder
from app.config import get_settings
from auth.identity import Identity
from parsing.ingest import PLATFORM_SHOP_ID, ingest_wiki

_DEV_EMBED_DIM = 1536  # must match db.models.Embedding.embedding (Vector(_EMBED_DIM))


class _EmbedderProto(Protocol):
    async def embed(self, texts: list[str]) -> list[list[float]]: ...


class _DeterministicDevEmbedder:
    """GD0.5 placeholder embedder — only selected by `default_embedder()` below when there is no
    `OPENAI_API_KEY` AND `OHANA_ENV=dev`. Since spec 05 Phase P1, `app/config.py` exists and
    `agent.providers.openai_embedder.OpenAIEmbedder` is the default whenever a key IS configured
    (any env) — this class is now the no-key dev fallback, not the unconditional default.

    Deterministic hash-based vectors, same shape `tests/test_wiki_rag.py`'s `FakeEmbedder`
    already uses to gate the ingest/search round-trip without a network call. This exercises
    the real storage/HTTP contract (chunk count, DB rows) for real; it is NOT representative
    of real semantic search quality — `tests/test_wiki_rag_live.py` (`@pytest.mark.live`) is the
    real-embedding acceptance check (ISSUE-016), run manually with a real key.

    Refuses to run outside dev (see `embed`) — defense in depth: even if selection logic above
    ever mis-picks this class outside dev, `embed()` itself still refuses. A docstring saying
    "placeholder" does not make a placeholder safe — the same reasoning that gated
    `auth.identity.get_jwt_secret`'s dev fallback on `OHANA_ENV` applies here.
    """

    async def embed(self, texts: list[str]) -> list[list[float]]:
        # Fail LOUD outside dev rather than returning hash vectors that look like embeddings.
        # The failure mode this closes is silent-wrong, not crash: ingest would answer
        # {"success": true, "chunks": N} while writing semantically meaningless vectors, so
        # `search_wiki` would then feed near-random chunks to the drafter and the AI would
        # answer a customer confidently from the wrong source. Nobody sees a stack trace; they
        # see a plausible wrong reply. Raising here (not in `default_embedder()` — see that
        # function's docstring) keeps `app/main.py` importable (P0/P1 screens stay up) and
        # confines the blast radius to this one route.
        if os.environ.get("OHANA_ENV") != "dev":
            raise RuntimeError(
                "Wiki ingest is unavailable: no real embedder is configured "
                "(no OPENAI_API_KEY outside dev). Refusing to write placeholder vectors "
                "outside dev — they would silently corrupt wiki-RAG answers."
            )
        out: list[list[float]] = []
        for t in texts:
            vec = [0.0] * _DEV_EMBED_DIM
            for tok in t.lower().split():
                vec[hash(tok) % _DEV_EMBED_DIM] = 1.0
            out.append(vec)
        return out


def default_embedder() -> _EmbedderProto:
    """Factory `app/main.py` calls at wiring time (spec 05 §3 Sub-task B). Env-selecting:

    - `OPENAI_API_KEY` set (any env, incl. dev) -> real `OpenAIEmbedder` (ISSUE-016 fix).
    - No key (any env) -> `_DeterministicDevEmbedder`.

    **Deviation from spec §3 B's proposed pseudocode, flagged at ANCHOR:** the spec's factory
    sketch raises `RuntimeError` directly in this function for the "no key + not dev" branch.
    This function deliberately does NOT do that — `app/main.py` calls `default_embedder()` at
    MODULE IMPORT time (`app.include_router(build_admin_router(default_embedder(), ...))` runs
    at import, before even `/health` is defined), not per-request. Raising here would crash the
    entire app's import — every route (health check, inbox, static SPA), not just wiki ingest —
    on any deploy that's missing `OHANA_ENV=dev` without a key configured yet. Confirmed via
    `pytest tests/ -m 'not live'`: with the eager raise, collection itself fails
    (`ERROR collecting tests/test_smoke.py`) before a single test runs.

    That also contradicts this codebase's established convention: env gates are checked
    PER-REQUEST, never baked in at import/build time (see `api/mock_auth.py::_is_dev_env`'s
    docstring, same reasoning). The safety property spec actually wants — never silently write
    placeholder vectors outside dev — is fully preserved: `_DeterministicDevEmbedder.embed()`
    already raises on first real use outside dev (unchanged since before this phase; see its
    docstring). This factory just doesn't ALSO raise a step earlier, at construction, where the
    only caller happens to run at import time.
    """
    settings = get_settings()
    if settings.openai_api_key:
        return OpenAIEmbedder()
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
