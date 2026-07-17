"""FastAPI entrypoint — GD0.5 adds `/api/*` (spec 01 backend, mounted here for the first
time) and the built SPA shell at `/` (spec 04 Phase P0). Router construction stays
factory-based (`build_router(...)`) to match the existing `api/inbox.py` shape — this file
is the ONLY place that wires concrete dependencies (session factory, identity dependency)
into those factories.

Mount order matters: API routers are included BEFORE the `web/dist` static mount. Starlette
matches routes in registration order and `StaticFiles(html=True)` at `/` is a catch-all — if
it were mounted first, it would shadow every `/api/*` request.

Only `api/inbox.py` and the new dev-only `api/mock_auth.py` are mounted at P0. `api/admin.py`
mounting is spec 04 Phase P2's concern (it lands together with the `require_admin` guard —
mounting it unguarded now would expose an unauthenticated wiki-ingest endpoint through the
live app before that guard exists). `api/webhook.py` needs a concrete `Drafter` — no
implementation of that protocol exists yet in `agent/` (spec 01 shipped the orchestrator
against the protocol, not a drafter) — so wiring it here would mean inventing throwaway glue
outside this phase's scope; deferred to whichever phase adds a real drafter.
"""

from __future__ import annotations

import secrets
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import RequestResponseEndpoint
from starlette.responses import Response as StarletteResponse

from api.inbox import build_router as build_inbox_router
from api.mock_auth import build_router as build_mock_auth_router
from auth.identity import CSRF_COOKIE_NAME, CSRF_HEADER_NAME, identity_from_cookie
from db.session import make_session_factory

app = FastAPI(title="Ohana AI Seller", version="0.1.0")

_session_factory = make_session_factory()

app.include_router(
    build_inbox_router(_session_factory, identity_from_cookie),
    prefix="/api",
)
app.include_router(build_mock_auth_router(), prefix="/api")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


# ---- CSRF (double-submit cookie) ----------------------------------------------------------
# Only state-mutating requests under /api are checked. `/api/mock/authorize` is exempt: it's
# the bootstrap route that MINTS the session (and the CSRF cookie itself) — there is no
# session yet for a forged cross-site POST to ride on, and requiring the header here would
# make the route uncallable from a fresh browser with no cookies at all. The routes this
# actually protects are `POST /api/inbox/{id}/approve|reject`, mounted in Phase P1.
_CSRF_EXEMPT_PATHS = {"/api/mock/authorize"}
_CSRF_SAFE_METHODS = {"GET", "HEAD", "OPTIONS"}


@app.middleware("http")
async def enforce_csrf_double_submit(
    request: Request, call_next: RequestResponseEndpoint
) -> StarletteResponse:
    if request.method not in _CSRF_SAFE_METHODS and request.url.path not in _CSRF_EXEMPT_PATHS:
        cookie_token = request.cookies.get(CSRF_COOKIE_NAME)
        header_token = request.headers.get(CSRF_HEADER_NAME)
        if (
            not cookie_token
            or not header_token
            or not secrets.compare_digest(cookie_token, header_token)
        ):
            return JSONResponse(status_code=403, content={"detail": "csrf_check_failed"})
    return await call_next(request)


# ---- Static SPA shell (spec 04 Phase P0) --------------------------------------------------
# Built via `cd web && pnpm install && pnpm build` — NOT run automatically here. Mounted LAST
# (see module docstring) and only if the build output exists, so a fresh checkout that
# hasn't run the Node build yet fails loudly per-request (404) rather than at import time.
_WEB_DIST = Path(__file__).resolve().parent.parent / "web" / "dist"
if _WEB_DIST.is_dir():
    app.mount("/", StaticFiles(directory=_WEB_DIST, html=True), name="web-spa")
