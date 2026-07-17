"""P0 gate (spec `05-Task-OhanaAISeller-ConfigEmbedder-F1.md` §7 Phase P0).

Written BEFORE `app/config.py` exists — expected RED (collection error: `ModuleNotFoundError:
No module named 'app.config'`) until the module lands. Locks the contract both
`agent/providers/openai_embedder.py` and `agent/providers/openai_client.py` need:
`Settings(BaseSettings)` + `get_settings()` exposing `openai_api_key`, `openai_embed_model`,
`openai_model`, `reasoning_models`.

`get_settings()` is `@lru_cache`d (singleton) — any test that mutates env MUST call
`get_settings.cache_clear()` first, else it silently asserts on a stale cached instance from
a prior test (a tautology that would pass even if env-reading were broken). Every test below
that touches env calls `cache_clear()` both before AND after (before: don't read a previous
test's cached instance; after: don't leak a monkeypatched instance to tests that run later in
the same process, since monkeypatch undoes the env var but not an already-cached Settings
object).
"""

from __future__ import annotations

import pytest


@pytest.fixture(autouse=True)
def _clear_settings_cache() -> None:
    """Every test starts and ends with a clean `get_settings()` cache — see module docstring."""
    from app.config import get_settings

    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_openai_embed_model_default_locked() -> None:
    """Q1 (spec §14) locks `text-embedding-3-small` — 1536 dims, matches the existing
    `Embedding.embedding Vector(1536)` column. Changing this default needs a migration; it is
    NOT this test's job to allow that silently."""
    from app.config import get_settings

    assert get_settings().openai_embed_model == "text-embedding-3-small"


def test_openai_api_key_none_when_env_unset(monkeypatch: pytest.MonkeyPatch) -> None:
    """Dev-without-key path (DoD #1) — must not raise, must be None (not empty string, not a
    placeholder literal)."""
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    from app.config import get_settings

    get_settings.cache_clear()
    assert get_settings().openai_api_key is None


def test_openai_api_key_reads_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """Empirical check that pydantic-settings actually maps `OPENAI_API_KEY` (env) ->
    `openai_api_key` (field) — do not trust the docs, prove it."""
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test-xyz")
    from app.config import get_settings

    get_settings.cache_clear()
    assert get_settings().openai_api_key == "sk-test-xyz"


def test_openai_embedder_imports_without_raising() -> None:
    """Proves `app.config` exists with a shape `OpenAIEmbedder` can import — this is the exact
    line that raised `ModuleNotFoundError` before P0 (ISSUE-016 root cause)."""
    from agent.providers.openai_embedder import OpenAIEmbedder  # noqa: F401


def test_settings_shape_satisfies_openai_client_needs() -> None:
    """Proves `openai_model` + `reasoning_models` are present on `Settings` with the shape
    `OpenAIClient` needs — `openai_model` used as `str` default-model, `reasoning_models` used
    as `model in get_settings().reasoning_models` (openai_client.py:118,252).

    NOT `from agent.providers.openai_client import OpenAIClient` directly — that import is
    blocked by a SEPARATE, pre-existing dead import unrelated to Settings shape: `from app
    import alert_service` (openai_client.py:28, `app/alert_service.py` never ported — see
    ISSUE-010, `app.config` was only half the gap it names). Fixing that is a new module,
    outside this phase's ALLOWED_FILES (`app/config.py`, `tests/test_config.py`) — flagged at
    ANCHOR for Wyatt, not silently pulled into P0 scope. `test_openai_client_import_blocked_by_
    unported_alert_service` below documents the current, still-broken state explicitly instead
    of pretending this test covers it."""
    from app.config import get_settings

    settings = get_settings()
    assert isinstance(settings.openai_model, str) and settings.openai_model
    assert hasattr(settings.reasoning_models, "__contains__")  # supports `model in ...`


@pytest.mark.xfail(
    reason="ISSUE-010: app/alert_service.py never ported (openai_client.py:28 `from app import "
    "alert_service`) — separate from app.config, out of P0 ALLOWED_FILES. Remove this xfail "
    "once that module lands; XPASS (strict) will force that cleanup instead of it going unnoticed.",
    strict=True,
)
def test_openai_client_import_blocked_by_unported_alert_service() -> None:
    from agent.providers.openai_client import OpenAIClient  # noqa: F401


def test_reasoning_models_supports_membership_test() -> None:
    """`openai_client.py:252` does `model in get_settings().reasoning_models` — field must be a
    collection (not e.g. a comma-string) for that to behave as intended."""
    from app.config import get_settings

    assert "gpt-4o" not in get_settings().reasoning_models  # empty by default (P0 doesn't wire)
