"""Settings foundation (spec `05-Task-OhanaAISeller-ConfigEmbedder-F1.md` §7 Phase P0).

Exists so `agent/providers/openai_embedder.py` and `agent/providers/openai_client.py` — both
ported from `drnickv4/` doing `from app.config import get_settings` — resolve. Before this
module existed, `OpenAIEmbedder()` raised `ModuleNotFoundError` (ISSUE-016 root cause), which
is why F1 wiki-RAG was never verified against a real embedder despite being tick DONE.

Scope is P0 only: the 4 fields the two providers reference. Wiring `OpenAIEmbedder` into the
live `default_embedder()` factory (`api/admin.py`) is Phase P1, not here.

`openai_model` and `reasoning_models` get defaults (rather than being required) so
`get_settings()` works with zero env configured — the dev-without-key path P0 exists to keep
alive. Neither field is exercised by any live code path yet (the LLM client isn't wired into
`app/main.py`); the defaults only need to let `OpenAIClient` import + instantiate without
raising, not represent a real deployment choice.
"""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # No `env_file` — read from process env only, matching how every other env-reader in this
    # repo works (`db/session.py get_database_url`, `auth/identity.py get_jwt_secret`, both
    # `os.environ.get(...)` directly). A `.env`-file source would read a local dev file even
    # after `monkeypatch.delenv` clears `os.environ`, silently reintroducing the exact
    # stale-state trap this spec exists to close (see module docstring + P0 test docstring).
    model_config = SettingsConfigDict(extra="ignore")

    # None allowed — dev-without-key path (DoD #1). Read from env `OPENAI_API_KEY`
    # (pydantic-settings v2 is case-insensitive by default; verified empirically in
    # tests/test_config.py::test_openai_api_key_reads_from_env, not just assumed from docs).
    openai_api_key: str | None = None

    # Q1 (spec §14) LOCKED — 1536 dims, matches `Embedding.embedding Vector(1536)`
    # (db/models.py `_EMBED_DIM`). Changing this needs an Alembic migration + reindex; do not
    # edit the default here without one (see spec §8).
    openai_embed_model: str = "text-embedding-3-small"

    # `agent/providers/openai_client.py OpenAIClient.__init__` needs this field to exist so the
    # import + instantiation don't raise, even though the client isn't wired into any live path
    # yet (P0 scope is "imports resolve", not "chat client works"). Default is a real, current
    # OpenAI chat model string rather than a placeholder — an unwired-but-importable client
    # should not carry a fake model id that would silently 404 if someone reached for it before
    # the real wiring phase lands.
    openai_model: str = "gpt-4o-mini"

    # `agent/providers/openai_client.py:252` does `model in get_settings().reasoning_models`
    # (membership test) — frozenset gives that O(1) with immutable-by-default semantics. Empty
    # by default: no model is in "reasoning mode" until a future phase wires the client and
    # deliberately opts models in.
    reasoning_models: frozenset[str] = frozenset()


@lru_cache
def get_settings() -> Settings:
    return Settings()
