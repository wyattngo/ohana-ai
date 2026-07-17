"""Admin ingest endpoints (F1 — wiki corpus loader).

GĐ0 accepts raw text via JSON; a docx/pdf upload path can wrap `parsing.extract.extract_text`
in a later phase. This endpoint is unauthenticated at GĐ0 — Phase 3+ will require an admin
JWT (auth.identity extended with role="admin" check). Do NOT expose this route publicly
until that gate lands.
"""

from __future__ import annotations

from typing import Protocol

from fastapi import APIRouter
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from parsing.ingest import PLATFORM_SHOP_ID, ingest_wiki


class _EmbedderProto(Protocol):
    async def embed(self, texts: list[str]) -> list[list[float]]: ...


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
) -> APIRouter:
    router = APIRouter(prefix="/admin", tags=["admin"])

    @router.post("/wiki/ingest", response_model=WikiIngestResponse)
    async def wiki_ingest(req: WikiIngestRequest) -> WikiIngestResponse:
        n = await ingest_wiki(
            session_factory,
            embedder,
            text=req.text,
            source_ref=req.source_ref,
            shop_id=req.shop_id,
        )
        return WikiIngestResponse(success=True, chunks=n)

    return router
