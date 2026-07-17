"""Verified identity (R1.1 extended for multi-tenant).

`Identity(user_id, shop_id, role)` is the sole source of tenant scope. `shop_id` MUST
come from a signed JWT claim — never from a request body, header, or webhook payload
(the platform never trusts client-supplied tenancy). `verify_token` rejects tokens that
omit `shop_id` outright: there is no default fall-through, because "missing shop_id" is
indistinguishable from "attacker forged a token for a shop they don't own" if we allow one.

Algorithm is pinned to a literal list (HS256 for GĐ0 shared-secret dev flow; RS256 is a
Phase 3+ upgrade). Reading it from config would open the classic alg-confusion bypass.

`identity_from_cookie` (spec 04 P0) is the browser-flow counterpart to `verify_token`: it
sources the SAME signed token from the httpOnly `ohana_session` cookie instead of an
`Authorization` header, so a FastAPI route can depend on either transport while sharing one
verification path. No new trust surface is added — a forged/missing/expired cookie hits the
identical `verify_token` rejection as a forged header token, just re-shaped as a 401 HTTP
response instead of a raised exception.

`get_jwt_secret()` reads `OHANA_JWT_SECRET` via `app.config.Settings` (spec 05 Phase P2 —
migrated off the direct `os.environ.get(...)` it used before; `db/session.py` got the same
treatment). Its literal dev fallback is gated on `OHANA_ENV == "dev"` and raises anywhere
else; the reasoning for that gate (mint fail-closed + verify fail-open is not a safe pair) is
on the function itself.

P2 deliberately builds a FRESH `Settings()` per call instead of going through the
`@lru_cache`d `app.config.get_settings()`. `app/main.py` calls `default_embedder()` at
IMPORT time (spec 05 P1), which calls `get_settings()` and caches whatever env happened to
be present at first import of that module — in a test process, that can be before any test's
`monkeypatch.setenv/delenv` runs. Routing this security gate through that same cache would
mean `test_jwt_secret_refuses_public_fallback_outside_dev`'s `monkeypatch.delenv(...)` could
silently no-op against an already-cached instance, which is exactly the "gate looks green but
isn't actually exercising the fail-closed path" failure ISSUE-016 already burned this repo on
once (there, a mocked embedder; here, it would be a stale cache). A fresh `Settings()` has no
shared state to go stale — it reads `os.environ` at construction, same as the pre-P2 direct
read did on every call.
"""

from __future__ import annotations

from dataclasses import dataclass

import jwt
from fastapi import Depends, HTTPException, Request

from app.config import Settings

_ALLOWED_ALGOS = ["HS256"]

SESSION_COOKIE_NAME = "ohana_session"
CSRF_COOKIE_NAME = "ohana_csrf"
CSRF_HEADER_NAME = "X-CSRF-Token"


@dataclass(frozen=True)
class Identity:
    user_id: str
    shop_id: str
    role: str


def verify_token(token: str, *, secret: str) -> Identity:
    """Verify an HS256 JWT and project it to Identity.

    Raises:
        jwt.InvalidSignatureError: signature mismatch (bad secret / tampered token).
        jwt.InvalidTokenError (or subclass): any other JWT decode failure.
        ValueError: token decoded but the `shop_id` claim is missing/empty. Also raised
            if `sub` or `role` are missing — no silent defaults for identity fields.
    """
    claims = jwt.decode(token, secret, algorithms=_ALLOWED_ALGOS)

    sub = claims.get("sub")
    if not isinstance(sub, str) or not sub:
        raise ValueError("invalid_sub — token missing 'sub' claim")

    shop_id = claims.get("shop_id")
    if not isinstance(shop_id, str) or not shop_id:
        raise ValueError("invalid_shop_id — token missing 'shop_id' claim")

    role = claims.get("role")
    if not isinstance(role, str) or not role:
        raise ValueError("invalid_role — token missing 'role' claim")

    return Identity(user_id=sub, shop_id=shop_id, role=role)


def get_jwt_secret() -> str:
    """`OHANA_JWT_SECRET` via a fresh `Settings()` (see module docstring for why fresh, not
    the cached `get_settings()`). The literal dev fallback applies ONLY when
    `OHANA_ENV == "dev"`; anywhere else a missing secret raises rather than silently signing
    with a value that is public in git.

    The fallback cannot be scoped by the mock-authorize guard alone: that guard closes the
    route that MINTS tokens, but this secret also feeds the path that VERIFIES them
    (`identity_from_cookie`). A deploy that forgot `OHANA_JWT_SECRET` would 404 the mint route
    yet still accept any cookie forged with the public fallback — self-issued `shop_id`, full
    cross-tenant read (R1.22). Mint fail-closed + verify fail-open is not a safe pair, so the
    fallback is gated on the same dev signal as the mint route.
    """
    settings = Settings()
    if settings.ohana_jwt_secret:
        return settings.ohana_jwt_secret
    if settings.ohana_env != "dev":
        raise RuntimeError(
            "OHANA_JWT_SECRET is required outside dev — refusing the public dev fallback."
        )
    return "ohana-dev-insecure-secret-change-before-staging"


def identity_from_cookie(request: Request) -> Identity:
    """FastAPI dependency — derive `Identity` from the httpOnly `ohana_session` cookie
    (browser flow). Missing or invalid cookie -> 401, same shape either way (never reveal
    which — a present-but-invalid cookie and a missing one are indistinguishable to the
    caller, mirroring the no-default-fallthrough invariant `verify_token` already enforces).
    """
    token = request.cookies.get(SESSION_COOKIE_NAME)
    if not token:
        raise HTTPException(status_code=401, detail="missing_session_cookie")
    try:
        return verify_token(token, secret=get_jwt_secret())
    except (jwt.InvalidTokenError, ValueError) as exc:
        raise HTTPException(status_code=401, detail="invalid_session_cookie") from exc


def require_admin(identity: Identity = Depends(identity_from_cookie)) -> Identity:
    """FastAPI dependency (spec 04 P0) — layers a role check on top of `identity_from_cookie`.
    A missing/invalid session cookie still 401s (from the wrapped dependency, resolved first);
    an authenticated identity whose `role != "admin"` gets 403 here.

    Spec 04 §7 Phase P2 step 1 literally says "GET /api/admin/wiki/ingest với non-admin cookie
    → 403", but the route this guards (`api/admin.py`) is POST-only — a GET there 405s before
    ever reaching this dependency. The correct read is "POST with a non-admin cookie → 403",
    which is what this function (and `tests/test_admin_ui.py`) actually implements.

    403, not 404: this deliberately differs from `mock_authorize`'s and `api/inbox.py`'s "look
    like it doesn't exist" shape, which is aimed at callers with NO valid session at all. An
    authenticated seller hitting this route already knows they're logged in as a seller —
    confirming the admin route exists leaks nothing beyond what they could already infer.
    """
    if identity.role != "admin":
        raise HTTPException(status_code=403, detail="admin_role_required")
    return identity
