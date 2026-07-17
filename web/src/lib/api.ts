/**
 * Typed HTTP client for the seller-facing screens (spec 04 §7 Phase P1 step 3).
 *
 * Every request uses `credentials: 'include'` so the browser sends the httpOnly
 * `ohana_session` cookie the backend derives `shop_id` from (auth/identity.py
 * `identity_from_cookie`) — this file never knows or sends `shop_id` itself (spec 04 §10 PC2 /
 * CLAUDE.md R1.22: tenant scope only ever comes from the verified JWT, never the client).
 *
 * State-mutating requests (POST) echo the `ohana_csrf` cookie back as the `X-CSRF-Token`
 * header — the double-submit pair `app/main.py`'s `enforce_csrf_double_submit` middleware
 * checks (spec 04 §10 PC8). GET is a CSRF-safe method so it's exempt, matching the server.
 */

export interface PendingReplyOut {
  reply_id: string;
  conversation_id: string;
  customer_id: string;
  draft_text: string;
  intent: string;
  confidence: number;
  status: string;
}

export interface MockAuthorizeResult {
  oa_id: string;
  shop_id: string;
  role: string;
}

export class ApiError extends Error {
  readonly status: number;

  constructor(status: number, message?: string) {
    super(message ?? `request failed with status ${status}`);
    this.status = status;
    this.name = "ApiError";
  }
}

const CSRF_COOKIE_NAME = "ohana_csrf";
const CSRF_HEADER_NAME = "X-CSRF-Token";
const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

function readCookie(name: string): string | null {
  const match = document.cookie.match(
    new RegExp(`(?:^|; )${name.replace(/[.$?*|{}()[\]\\/+^]/g, "\\$&")}=([^;]*)`),
  );
  return match ? decodeURIComponent(match[1]) : null;
}

async function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const method = (init.method ?? "GET").toUpperCase();
  const headers = new Headers(init.headers);

  if (!SAFE_METHODS.has(method)) {
    const csrfToken = readCookie(CSRF_COOKIE_NAME);
    if (csrfToken) {
      headers.set(CSRF_HEADER_NAME, csrfToken);
    }
  }

  const response = await fetch(path, { ...init, method, headers, credentials: "include" });
  if (!response.ok) {
    throw new ApiError(response.status);
  }
  return response;
}

/** `GET /api/inbox` — parked drafts for the caller's shop, oldest-first. */
export async function fetchInbox(): Promise<PendingReplyOut[]> {
  const resp = await apiFetch("/api/inbox");
  return (await resp.json()) as PendingReplyOut[];
}

/** `POST /api/inbox/{id}/approve` — flips status to `approved`. Does NOT send the draft to
 * the customer — the send-on-approve worker doesn't exist yet (PRE-004, spec 04 §3 B.3). */
export async function approveReply(replyId: string): Promise<void> {
  await apiFetch(`/api/inbox/${encodeURIComponent(replyId)}/approve`, { method: "POST" });
}

/** `POST /api/inbox/{id}/reject` — flips status to `rejected`. */
export async function rejectReply(replyId: string): Promise<void> {
  await apiFetch(`/api/inbox/${encodeURIComponent(replyId)}/reject`, { method: "POST" });
}

/** `POST /api/mock/authorize` (dev-only, DEC-OHANA-01 U4) — mints the fixture dev session +
 * CSRF cookies. Real Zalo OAuth is spec 05+ (PRE-004). */
export async function mockAuthorize(role: "seller" | "admin" = "seller"): Promise<MockAuthorizeResult> {
  const resp = await apiFetch(`/api/mock/authorize?role=${encodeURIComponent(role)}`, {
    method: "POST",
  });
  return (await resp.json()) as MockAuthorizeResult;
}
