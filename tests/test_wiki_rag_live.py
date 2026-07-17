"""ISSUE-016 live acceptance (spec `05-Task-OhanaAISeller-ConfigEmbedder-F1.md` §7 Phase P1, DoD
#5). Mirrors `tests/test_wiki_rag.py::test_wiki_ingest_then_search_returns_hit` structurally
(same seed doc, same ingest -> search -> assert shape) but wires a REAL
`agent.providers.openai_embedder.OpenAIEmbedder` instead of the deterministic `FakeEmbedder`.

This is the ONLY test in this repo that proves F1 wiki-RAG retrieval works with real OpenAI
embeddings end-to-end. `tests/test_embedder_wiring.py` (the deterministic gate, runs in every
`-m 'not live'` pass) only proves the *factory* picks the right adapter class and the adapter's
*call shape* is correct against a mocked client — it never calls real OpenAI and therefore
cannot prove semantic retrieval quality. Conflating the two was the original ISSUE-016 mistake
(F1 shipped "DONE" gated only by `FakeEmbedder`, never run against a real embedder). Do not
delete or weaken this distinction: if the deterministic gate starts asserting things about
retrieval *quality*, that's the same mistake again.

`@pytest.mark.live` — EXCLUDED from the default gate (`pyproject.toml` `addopts = "-q -m 'not
live'"`). Requires a real `OPENAI_API_KEY` (network call to OpenAI) AND a live Postgres with
pgvector at `DATABASE_URL` (same env as `tests/test_wiki_rag.py`). Wyatt/Tân run this manually
as the DoD #5 acceptance step — it is NOT run by CI or by any executor session, since neither
has a real key. Run with:

    OPENAI_API_KEY=sk-... .venv/bin/python -m pytest tests/test_wiki_rag_live.py -m live -x -q

PASS here is what actually closes ISSUE-016 — a green deterministic gate alone does not.
"""

from __future__ import annotations

import os

import pytest

DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql+psycopg://ohana:ohana@localhost:5432/ohana"
)


@pytest.mark.live
@pytest.mark.asyncio
async def test_wiki_ingest_then_search_returns_hit_with_real_embedder() -> None:
    """Real `OpenAIEmbedder`, real OpenAI network call, real Postgres+pgvector. Ingest one wiki
    doc (same seed text as `test_wiki_rag.py`) then search for a question about it — the chunk
    containing the answer must be the top hit, proven via ACTUAL semantic nearest-neighbor (not
    the FakeEmbedder's keyword-overlap-in-a-hash-slot approximation)."""
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

    from agent.providers.openai_embedder import OpenAIEmbedder
    from db.models import Base
    from parsing.ingest import ingest_wiki
    from tools.wiki import search_wiki

    engine = create_async_engine(DATABASE_URL, echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    embedder = OpenAIEmbedder()  # real client — reads OPENAI_API_KEY via app.config.get_settings()

    wiki_text = (
        "Ohana is a seller AI copilot for Vietnamese social commerce. "
        "It integrates Zalo OA to draft replies for sellers.\n\n"
        "Return policy: buyers may return items within 7 days of delivery "
        "provided the packaging is intact."
    )
    n = await ingest_wiki(
        session_factory,
        embedder,
        text=wiki_text,
        source_ref="wiki:overview",
    )
    assert n >= 1, "ingest_wiki should return the number of chunks stored"

    hits = await search_wiki(
        "What is the return policy for buyers?",
        embedder=embedder,
        session_factory=session_factory,
    )

    await engine.dispose()

    assert len(hits) >= 1, "search_wiki should surface at least one chunk"
    assert any("return" in h.chunk.lower() for h in hits), (
        "top wiki hits should include the chunk about the return policy — with a real embedder "
        "this is the actual semantic-search claim F1 makes to sellers, not an approximation"
    )
    for h in hits:
        assert h.namespace == "platform_wiki", (
            f"search_wiki must stay in platform_wiki namespace, got {h.namespace!r}"
        )
