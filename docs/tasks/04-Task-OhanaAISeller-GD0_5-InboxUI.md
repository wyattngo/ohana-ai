# 04-Task-OhanaAISeller-GD0_5-InboxUI

<!-- spec-generator v2.3 · Branch B (raw brief từ Wyatt, no v3 marker) -->
<!-- PROJECT: Ohana AI Seller. GĐ0.5 = cầu nối GĐ0 (backend DONE) → GĐ1. -->
<!-- ADP:MANIFEST inherit từ ohana-ai/CLAUDE.md §5. KHÔNG override. -->
<!-- Parent: 01-Task-OhanaAISeller-GD0.md (DONE 2026-07-17). Spec 02 = bootstrap fork. Spec 03 = backfill. Spec 04 = UI. -->

## §0 — Header

| Field | Value |
|---|---|
| Title | Ohana AI Seller — GĐ0.5 Inbox UI (HITL review surface) |
| Parent | [01-Task-OhanaAISeller-GD0.md](01-Task-OhanaAISeller-GD0.md) §12 (resolve `web/` [UNVERIFIED]) |
| Depends-on | Spec 01 Phase 5 DONE (`api/inbox.py` + `api/admin.py` + `api/webhook.py` all landed). Không depend PRE-002/003/004 backfill. |
| Owner | R: Tân (dev lead) · A: Wyatt (fractional CTO, framework choice + RISK tier) |
| Branch | `feat/gd0_5-inbox-ui` (chưa tạo — task đầu tiên là init branch) |
| Duration ước lượng | 3–5 ngày sau khi Wyatt lock U1–U4 (framework quyết định = 40% effort) |
| Spec type | Full (14-section, Ohana-adapted — §4 dùng priority filter, KHÔNG dùng Survival Framework fintech) |
| Workflow mode | IMPLEMENT (sau khi U1–U4 locked) |
| inherited_from | — (Branch B từ conversation Wyatt 2026-07-17 sau khi share mockup) |
| RISK proposed | P0=medium · P1=medium · P2=low — Wyatt finalize |

> **Priority order (Ohana):** safety → user trust → stability → growth. §4 dùng bộ này, KHÔNG dùng LR/WP/TV/UR (Ohana không có money surface).

---

## §1 — Problem Statement

Backend GĐ0 (spec 01) đã 100% DONE với 5 HTTP endpoints live nhưng **không có mặt bằng UI nào** để seller thực sự dùng. Cụ thể:

- `GET /inbox` trả về `list[PendingReplyOut]` — không ai render.
- `POST /inbox/{id}/approve|reject` — không nút bấm.
- `POST /admin/wiki/ingest` — không form upload, chỉ curl.
- `POST /webhook/zalo/{oa_id}` — `enabled=False` default, chờ PRE-004 nhưng UI channel-picker chưa có nên khi PRE-004 landed vẫn không click được.

Spec 01 §12 marked `web/` là [UNVERIFIED] — framework choice defer. Tình trạng hiện tại: Phase 5 gate GREEN (12/12 test) nhưng **seller không dùng được sản phẩm**. Đây là chặn ship soft-launch GĐ1.

**Mockup Wyatt share (`~/Downloads/seller_ai_copilot_demo.jsx`, 744 LOC React)** cho thấy shape UX đúng cho F3 (inbox + review + approve/reject) nhưng KHÔNG dùng thẳng được vì 4 blocker:

| Blocker | File / dòng | Vấn đề | Fix trong spec này |
|---|---|---|---|
| B1. Credential leak | `callClaude()` line 170–177 | `fetch("https://api.anthropic.com/v1/messages")` từ browser → API key phải nằm client-side | Backend orchestrator (Phase 5) đã soạn draft server-side → UI chỉ render `draft_text`. XOÁ `callClaude` khỏi client. |
| B2. No tenant scoping | Line 8–15 `SHOP = { name: "Shop Thời Trang Mai" }` hardcode | Không có `shop_id`/JWT — vi phạm R1.22 khi wire lên backend tenant-first | JWT trong httpOnly cookie, mọi fetch `/api/inbox` tự carry cookie. UI KHÔNG biết `shop_id` (backend derive từ Identity). |
| B3. Chat auto-send model | Line 201–206 `sendShop()` | Mockup: seller gõ → gửi thẳng khách. Backend: draft parked → seller approve/reject → worker (chưa build) send. | UI GĐ0.5 chỉ có 2 nút "Duyệt" / "Từ chối", KHÔNG có textarea free-typing. |
| B4. 60% feature là GĐ2+/GĐ3+ | Line 468–504 (orders dashboard), 541–556 (payments + analytics), 515–524 (plans/credits) | Order/COD/carrier/timeline = GĐ2 F4. Payment/MoMo/QR = GĐ3+. Plans/credits = billing GĐ3+. | Cắt hết. Chỉ port screens: onboarding channel picker · inbox · review card. Admin ingest = màn thứ 4 KHÔNG có trong mockup. |

**Evidence (đã verify on-disk 2026-07-17):**
- `ohana-ai/api/inbox.py` — 96 LOC, 3 endpoints, tenant-scoped qua `identity_dep`.
- `ohana-ai/api/webhook.py` — 89 LOC, `enabled=False` default, `_oa_to_shop` stub in-memory.
- `ohana-ai/api/admin.py` — 52 LOC, `POST /admin/wiki/ingest` unauth (chờ role check Phase 3+).
- `ohana-ai/app/main.py` — FastAPI entry, sẽ cần route mount cho `/api/*` proxy + static bundle serve.
- `ohana-ai/pyproject.toml` — Python 3.11, FastAPI 0.110+, KHÔNG có Node/React deps. `redis>=5.0` declared nhưng chưa wire (Phase 3+).

---

## §2 — Goal

**VI:** Ship UI GĐ0.5 với 4 màn (channel picker mock → inbox list → review card → admin wiki ingest) live-bind vào backend spec 01. Seller Zalo có thể mở URL, thấy pending drafts, duyệt hoặc từ chối. Framework `web/` resolved (Wyatt lock U1). KHÔNG scope orders/payments/analytics/plans.

**EN:** Ship GĐ0.5 seller-facing UI with 4 screens (channel picker · inbox · review card · admin wiki ingest) bound to spec 01 backend. Sellers can review and decide parked drafts through a browser. Framework choice for `web/` locked by Wyatt via U1 resolution.

**DoD (Definition of Done):**
1. `web/` scaffold committed, framework decision documented trong `docs/decisions/`.
2. Inbox live-render >= 1 draft từ real `GET /inbox` (fixture-seeded qua `test_inbox_ui.py`).
3. Approve/reject nút wire — click → HTTP 200 → status flip trong DB.
4. Admin ingest form → POST `/admin/wiki/ingest` với text sample → response `{ success: true, chunks: N }` render.
5. E2E gate: `tests/test_inbox_ui_e2e.py` chạy `draft → approve → status='approved'` PASS.
6. Không có Anthropic API key nào ở client bundle (grep verify).
7. Không có `shop_id` hardcoded trong client code (grep verify — backend derive từ JWT).

---

## §3 — Scope

### Sub-task A (Phase P0) — Framework decision + `web/` scaffold

**What:** Wyatt lock U1 (framework choice). Scaffold `web/` với minimal build, proxy `/api/*` sang FastAPI, JWT trong httpOnly cookie, không có Anthropic key ở client.

**Files (proposed — depend U1 outcome):**
- `web/` NEW — toàn bộ subdir (package.json/vite.config nếu Vite; app-router structure nếu Next.js; templates/ + static/ nếu Jinja+HTMX)
- `app/main.py` EDIT — mount static bundle `web/dist/` (Vite/Next) hoặc `web/templates/` + `web/static/` (Jinja)
- `auth/identity.py` EDIT (minor) — thêm helper `identity_from_cookie(request)` để FastAPI dep có thể đọc từ httpOnly cookie thay vì header `Authorization: Bearer` (backend hiện chỉ hỗ trợ header — needed cho browser flow)
- `docs/decisions/DEC-OHANA-01-web-framework.md` NEW — ADR ghi rationale + rejected options

**Endpoint:** Không endpoint mới — dùng lại 5 endpoints spec 01. Mount static ở `/` hoặc `/app` (Wyatt quyết).

**RISK:** medium (proposed). ALLOWED_FILES overlap RISK_PATHS: `auth/identity.py`. Cụ thể: đổi identity derive từ header → cookie = broaden trust surface (cookie có thể bị CSRF, header thì không). Cần thêm CSRF token cho state-mutating endpoints (POST approve/reject).

### Sub-task B (Phase P1) — 3 màn seller-facing

**What:** Port UX từ mockup (design tokens + screen shapes), rebuild logic bằng backend-driven model.

**B.1 Channel picker + authorize (mock cho tới PRE-004)**
- Port UX từ mockup lines 299–354 (`view === "connect"` + `view === "authorize"` + `connecting/syncing`).
- Cắt: `CHANNELS` cứng 3 kênh (Zalo/FB/TikTok) → giữ nguyên. Zalo `available: true`, FB `available: false`, TikTok `available: false` (GĐ0.5 chỉ Zalo).
- Wire `Cho phép & kết nối` button → **mock endpoint** `POST /api/mock/authorize` trả về `{ oa_id: "fixture-oa-001", shop_id: "fixture-shop-001" }`, set httpOnly cookie với dev JWT. Real OAuth flow = spec 05+ khi PRE-004 landed.

**B.2 Inbox**
- Port UX từ mockup lines 375–403 (`view === "inbox"`).
- **Đổi semantics:** mockup renders `INIT_CONVS` (mock conversations). GĐ0.5 renders `PendingReplyOut[]` từ `GET /inbox`.
- Mỗi row hiển thị: `customer_id` (as avatar+name), `draft_text` preview (2 lines), intent badge, confidence bar, status badge (`pending/approved/rejected`).
- **Intent badge — AMENDED 2026-07-17 (Wyatt, tại ANCHOR P1).** Bản gốc yêu cầu color-coded (`refund/complaint`=red, `order_question`=yellow, `general`=green). Không thực hiện được: Astronixa design system KHÔNG có semantic palette — cả 6 family đều là hue (primary tím `#9744FB`, secondary xanh `#2E96FE`, tertiary magenta `#CA50FB`, accent cyan `#00F0FF`, neutral `#7C7481`, greyscale). Bịa hex ngoài `tokens.ts` sẽ phá single-point-of-change contract của DEC-OHANA-01 §U2. **Chốt:** phân biệt intent bằng **icon + label tiếng Việt** trên chip greyscale — accessible hơn màu đơn thuần (color-blind safe). `intentMeta()` để ngỏ để thêm màu nếu Astronixa bổ sung semantic palette sau.
- Refresh: polling 10s (KHÔNG SSE — spec 01 §12 note "SSE parity chưa xác nhận"), Wyatt confirm sau nếu cần realtime.

**B.3 Review card**
- Port UX từ mockup lines 405–466 (`view === "chat"`) NHƯNG cắt: bỏ textarea free-typing, bỏ AI-suggestion sheet (`suggesting || suggestion`), bỏ CreditBadge, bỏ QuickBtn row (order/pay/analytics).
- Layout: header (customer_id + intent), conversation context (nếu có — lấy từ `conversation_id` — **[U5 UNVERIFIED]** endpoint fetch conversation history chưa có, có thể fake bằng cách chỉ hiện `draft_text` ở GĐ0.5), draft body (read-only), 2 buttons: **Duyệt** (green primary) + **Từ chối** (red ghost).
- Click Duyệt → `POST /inbox/{id}/approve` → toast "Đã duyệt — worker sẽ gửi cho khách khi PRE-004 landed" → back to inbox, row status → `approved`.
- Click Từ chối → confirmation dialog "Bạn muốn từ chối? Draft sẽ không gửi khách" → `POST /inbox/{id}/reject` → back to inbox.

**Files (proposed):**
- `web/src/screens/ChannelPicker.tsx` (or `.jsx`/`.html` per U1) NEW
- `web/src/screens/Inbox.tsx` NEW
- `web/src/screens/ReviewCard.tsx` NEW
- `web/src/lib/api.ts` NEW — typed HTTP client fetch `/api/inbox`, `/api/inbox/:id/approve|reject`, `/api/mock/authorize`
- `web/src/lib/tokens.ts` NEW — design tokens (colors, spacing, typography) freeze từ mockup nếu U2 = "adapt from mockup"
- `api/mock_auth.py` NEW — dev-only mock authorize endpoint, guard behind `settings.env == "dev"` (KHÔNG mount ở production)
- `tests/test_inbox_ui_e2e.py` NEW — Playwright/httpx e2e gate

**RISK:** medium (proposed). ALLOWED_FILES overlap RISK_PATHS: `auth/` (nếu mock_auth issue JWT). Không chạm `agent/`, `bridge/`, `db/migrations` → không phải high.

### Sub-task C (Phase P2) — Admin wiki ingest UI

**What:** Form đơn giản cho ingest doc vào `platform_wiki` namespace.

- 2 field: textarea `text`, input `source_ref` (freeform, ví dụ `"policy-v1"`, `"shipping-faq"`).
- **`min 100 chars` — AMENDED 2026-07-17 (tại ANCHOR P2).** Bản gốc ghi "min 100 chars" cho textarea; reviewer đọc thành data contract và flag backend `min_length=1` là "validation bypass". **Không sửa backend.** Lý do: caller của route này là **admin đã xác thực** — người vốn đã ingest được nội dung tuỳ ý dài ≥100 ký tự. Ép 100 server-side không chặn rác, chỉ chặn rác NGẮN, đổi lại từ chối fact hợp lệ (`"Freeship đơn từ 400k."` = 21 ký tự là mục wiki chính đáng). Lợi ích ~0, chi phí là false-reject dữ liệu thật. **Chốt:** `100` là **gợi ý UX client-side** (`MIN_TEXT_LENGTH` disable nút submit, chống paste nhầm), backend giữ `min_length=1`. Ngưỡng thật (nếu cần) chỉ xác định được khi PRE-003 land wiki thật và biết độ dài doc điển hình — xem ISSUE-015.
- 1 button `Ingest`.
- Trên submit: `POST /admin/wiki/ingest` với `{ text, source_ref, shop_id: "platform_wiki" }` (hardcode `PLATFORM_SHOP_ID` = shared namespace per spec 01 Phase 3).
- Response: hiển thị `chunks: N` và toast success. Trên error: hiển thị message.
- **Guard:** URL `/admin/*` cần role=admin từ JWT — spec 01 §12 admin note "Phase 3+ will require an admin JWT". GĐ0.5 sẽ dùng fixture admin JWT (cùng dev cookie flow, cờ `role="admin"`).

**Files:**
- `web/src/screens/AdminWikiIngest.tsx` NEW
- `web/src/lib/api.ts` EDIT (thêm `postWikiIngest()`)
- `auth/identity.py` EDIT (thêm role check helper — chưa có `has_role("admin")` in-file)

**RISK:** low (proposed). Không chạm RISK_PATHS ngoài `auth/identity.py` helper mở rộng (đã đề cập P0 — có thể gộp vào P0 diff nếu tiện).

### Out of scope (defer sang spec 05+)

- Chat auto-suggest UI (backend orchestrator đã soạn — UI GĐ0.5 chỉ review, không compose)
- Orders / COD / carrier / shipping timeline (GĐ2 F4)
- Payments / MoMo / VietQR / ZaloPay integration (GĐ3+)
- Plans / credits / billing UI (GĐ3+)
- Analytics dashboard, per-shop metrics (GĐ2+)
- Real Zalo OA OAuth flow (chờ PRE-004 backfill — spec 05 sẽ handle)
- Real seller login (magic link / email OTP / OAuth) — GĐ0.5 dùng dev cookie fixture
- F2 read tools UI (order_status / shipping / product / account lookup) — chờ PRE-002 backfill
- SSE / websocket cho realtime inbox update — polling 10s đủ ở GĐ0.5
- Conversation history endpoint + UI (`GET /conversations/{id}/messages`) — **[U5]** flag, có thể defer
- Multi-language i18n — Vietnamese-only ở GĐ0.5
- Mobile responsive polish — mockup đã mobile-first 410×800, GĐ0.5 giữ nguyên shell, không optimize desktop

---

## §4 — Priority Filter (Ohana — safety → user trust → stability → growth)

| Priority | Question | Assessment |
|---|---|---|
| 1. Safety | UI có expose customer PII cross-shop không? | **PASS** — mọi fetch client-side qua `/api/*` proxy, backend enforce `identity.shop_id` scope. UI KHÔNG biết `shop_id` để có thể leak. |
| 1. Safety | UI có bypass policy_gate (Phase 5) không? | **PASS** — approve chỉ flip status. Send-on-approve worker (chưa build) là chỗ duy nhất outbound Zalo call. UI KHÔNG send. |
| 1. Safety | UI có expose Anthropic API key trong bundle không? | **MUST-PASS** — post-check §10 grep verify. Fail = redesign (rollback DEC-OHANA-01). |
| 2. User trust | Seller có bị auto-send accidentally không? | **PASS** — không có nút "Send", chỉ "Duyệt". Duyệt chỉ flip status, worker gửi async (visible qua status badge). |
| 2. User trust | Reject có confirmation dialog không? | **PASS** — B.3 spec confirmation dialog. |
| 3. Stability | UI break flow orchestrator nếu backend down? | **PASS** — UI degrade graceful (loading spinner, error toast). Backend uptime = separate concern. |
| 4. Growth | Chỉ khi 1–3 satisfied — có measurable lead cho GĐ1? | **PASS** — GĐ1 = mở thêm seller lên platform. UI GĐ0.5 = tiền đề login/onboarding flow. |

### RED FLAG scan (Ohana-adapted)

- [ ] Client-side có Anthropic/OpenAI API key? → **NO** (post-check §10 verify)
- [ ] `shop_id` hardcoded trong client? → **NO** (post-check §10 verify)
- [ ] Approve/reject bypass tenant scope? → **NO** (backend enforce, spec 01 Phase 2)
- [ ] Auto-send parked draft mà không seller click? → **NO** (không có send-on-approve worker ở GĐ0.5)
- [ ] Admin ingest expose lên public URL? → **NO** (URL `/admin/*` guard role=admin, GĐ0.5 fixture)
- [ ] CSRF token thiếu cho POST endpoints khi dùng cookie auth? → **MUST-FIX** trong P0 (double-submit cookie hoặc `SameSite=strict`)

**Verdict:** PASS với 1 must-fix (CSRF) đưa vào P0 execute steps.

---

## §5 — Source Files & Context

Đọc trước khi run bất kỳ step nào:

1. [ohana-ai/CLAUDE.md](../../CLAUDE.md) — project router, ADP:MANIFEST §5, port table §3, anti-patterns §7
2. [01-Task-OhanaAISeller-GD0.md](01-Task-OhanaAISeller-GD0.md) — parent spec (đặc biệt §3 Sub-task E, §12 [UNVERIFIED] `web/` note)
3. [api/inbox.py](../../api/inbox.py) — endpoint contract (list + approve + reject)
4. [api/admin.py](../../api/admin.py) — wiki ingest contract
5. [api/webhook.py](../../api/webhook.py) — Zalo inbound (không edit ở spec này, chỉ đọc để hiểu `enabled=False` state)
6. [auth/identity.py](../../auth/identity.py) — Identity dataclass + FastAPI dep (need edit)
7. [app/main.py](../../app/main.py) — FastAPI entry (need mount)
8. `~/Downloads/seller_ai_copilot_demo.jsx` — mockup UX reference (design tokens + screen shapes, KHÔNG copy code)
9. [docs/adr/hook-contract.md](../adr/hook-contract.md) — ADP v2.3 hooks contract
10. `docs/memory/SESSION_LOG.md` — recent context (spec 01 close-out 2026-07-17)
11. `docs/decisions/DEC-OHANA-01-web-framework.md` — WILL BE CREATED trong P0 step 1

**Recent context:** Spec 01 = 100% DONE 2026-07-17. STATE_HASH `1b5cf0eabdfd`. PRE-002/003/004 defer backfill (không chặn UI). Wyatt approve spec 01 với priority order safety→trust→stability→growth (KHÔNG dùng LR/WP/TV/UR).

---

## §6 — Pre-flight Checks

> Run TRƯỚC bất kỳ code step nào. Paste output. STOP nếu red flag.

```bash
# PF1. Working tree clean
cd /Users/wyattngo/Sites/localhost/ohana-ai
git status
# Expected: chỉ 2 file untracked (docs/Roadmap.md, docs/tasks/03-Task-GD0-AcceptanceBackfill.md) — hoặc clean
# Red flag: uncommitted changes trong api/, auth/, agent/, web/ → rollback trước khi run

# PF2. Branch mới
git checkout -b feat/gd0_5-inbox-ui
# Expected: switched to new branch. Không có `feat/gd0_5-inbox-ui` cũ.
# Red flag: branch đã tồn tại → hỏi Wyatt (có commit cũ chưa merge không)

# PF3. Spec 01 Phase 5 committed
git log --oneline -10 | grep -E "phase-5|Spec 01|GD0.*DONE"
# Expected: thấy commit "phase-5: checkpoint" hoặc "meta: sync CLAUDE.md + memory after spec 01 = 100% DONE"
# Red flag: không thấy → Pattern J violation, backend chưa sẵn sàng cho UI

# PF4. Backend endpoints reachable (dev server up)
.venv/bin/python -m uvicorn app.main:app --port 8000 &
sleep 2
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/inbox
# Expected: 401 (unauthorized — chưa gửi JWT) hoặc 422 (validation) — nghĩa là endpoint LIVE
# Red flag: connection refused / 500 → backend broken, fix trước
kill %1

# PF5. Anthropic key NOT trong .env (bảo đảm sẽ không leak khi build client)
grep -r "ANTHROPIC_API_KEY\|OPENAI_API_KEY\|sk-ant-\|sk-proj-" .env* 2>/dev/null | grep -v "^\.env\.example"
# Expected: hits chỉ trong .env (server-side), KHÔNG trong .env.local hoặc bất kỳ file nào bundler có thể pick up
# Red flag: key trong .env.local với prefix `VITE_*` / `NEXT_PUBLIC_*` → sẽ leak vào client bundle

# PF6. Wyatt đã lock U1–U4 chưa?
cat docs/decisions/DEC-OHANA-01-web-framework.md 2>/dev/null
# Expected: file tồn tại với Wyatt-signed decision cho U1 (framework), U2 (brand), U3 (deploy), U4 (JWT)
# Red flag: file không tồn tại → STOP, chuyển sang Q&A với Wyatt (§14 Open Questions)

# PF7. Node/pnpm/yarn present nếu U1 = Vite hoặc Next
which node && node --version
# Expected (nếu U1 = Vite/Next): node >= 20
# N/A nếu U1 = FastAPI+Jinja+HTMX
```

**STOP nếu bất kỳ PF trả red flag → paste output, hỏi Wyatt trước khi proceed.**

---

## §7 — Execute Steps

> Numbered, atomic, one concern per step. TDD ordering trong mọi phase (test viết trước, RED trước impl).

### Phase P0 — Framework decision + `web/` scaffold

<!-- ADP:PHASE P0 -->
STATUS: DONE
EVIDENCE: commit=3e07293, gate_exit=0, duration=2s, review=PASS(judge=APPROVE,model=haiku,bound=ee8e9f6b888f,tier=medium), ran=2026-07-17T17:24
GOAL: Wyatt lock U1 via DEC-OHANA-01 → `web/` subdir scaffolded với chosen framework, `app/main.py` mount static/template, `auth/identity.py` mở rộng cookie-based derive + CSRF, dev-mock `POST /api/mock/authorize` endpoint, gate test `test_web_scaffold.py` PASS.
APPROACH:
  1. TDD gate: viết `tests/test_web_scaffold.py` với 4 test: (a) GET `/` trả 200 + HTML shell, (b) GET `/api/inbox` không cookie → 401, (c) GET `/api/inbox` với dev cookie → 200 + `[]`, (d) POST `/api/mock/authorize` set cookie + return `{oa_id, shop_id}`. Confirm RED.
  2. Đọc DEC-OHANA-01 (Wyatt-signed), tạo scaffold theo framework locked. Vite+React (recommended nếu Wyatt không override): `pnpm create vite web -- --template react-ts`, install `lucide-react` (match mockup icon set).
  3. `app/main.py`: mount static bundle. Add CSRF middleware (double-submit cookie).
  4. `auth/identity.py`: helper `identity_from_cookie(request) -> Identity` — parse JWT từ cookie `ohana_session`, verify HS256. Existing header-based dep vẫn kept cho API testing.
  5. `api/mock_auth.py` NEW: `POST /api/mock/authorize` guard `if settings.env != "dev": raise 404` — trả `{oa_id, shop_id}` fixture, set httpOnly cookie.
  6. Confirm gate test GREEN.
  7. Commit `adp/04 phase-p0: web/ scaffold + cookie auth + mock authorize` qua `bash .claude/tools/adp-checkpoint.sh`.
ALLOWED_FILES: web/, app/main.py, auth/identity.py, api/mock_auth.py, tests/test_web_scaffold.py, docs/decisions/DEC-OHANA-01-web-framework.md, pyproject.toml (nếu cần thêm dep như `itsdangerous` cho CSRF)
GATE: .venv/bin/python -m pytest tests/test_web_scaffold.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_web_scaffold.py tests/test_tenant_isolation.py tests/test_policy_gate.py tests/test_orchestrator.py -x -q
RETRY: 0/3
RISK: medium
REVIEW: PASS ref=docs/reviews/04-Task-OhanaAISeller-GD0_5-InboxUI-phase-P0.json
<!-- /ADP -->

### Phase P1 — 3 seller-facing screens

<!-- ADP:PHASE P1 -->
STATUS: DONE
EVIDENCE: commit=b557e53, gate_exit=0, duration=1s, review=PASS(judge=APPROVE,model=haiku,bound=985b9d445b08,tier=medium), ran=2026-07-17T17:56
GOAL: Channel picker + inbox list + review card wire vào backend. E2E test PASS cho flow draft → approve → status='approved'. Design tokens frozen (U2 outcome).
APPROACH:
  1. TDD gate: viết `tests/test_inbox_ui_e2e.py` với 3 test: (a) seed 1 PendingReply pending → GET `/api/inbox` với dev cookie → 200 + 1 row với đúng fields, (b) POST `/api/inbox/{id}/approve` → 200 + status flip trong DB, (c) POST `/api/inbox/{id}/reject` → 200 + status flip. Confirm RED (endpoints live nhưng chưa mounted).
  2. `app/main.py`: mount `api.inbox.build_router(...)` dưới prefix `/api` (không phải root — vì `/` giờ serve UI). Kiểm tra tất cả prefix collision.
  3. `web/src/lib/api.ts`: typed client cho 3 endpoint (list, approve, reject) + 1 endpoint mock authorize. Fetch với `credentials: 'include'` để browser gửi cookie. Header `X-CSRF-Token` từ meta tag hoặc cookie-echoed.
  4. `web/src/lib/tokens.ts`: freeze design tokens từ mockup nếu U2 = "adapt". Colors: primary gradient `#4F46E5→#7C3AED`, success `#10B981`, warning `#F59E0B`, danger `#B91C1C`. Spacing 8pt grid. Typography Inter/system-ui.
  5. `web/src/screens/ChannelPicker.tsx`: port từ mockup lines 299–354. Cắt Facebook + TikTok (disabled), chỉ Zalo actionable. Click → `POST /api/mock/authorize` → redirect Inbox.
  6. `web/src/screens/Inbox.tsx`: fetch `/api/inbox`, render list, poll 10s. Empty state: "Chưa có tin nhắn cần duyệt". Loading spinner. Error toast.
  7. `web/src/screens/ReviewCard.tsx`: nhận `reply_id` từ route param, render draft. 2 nút Duyệt (primary) + Từ chối (ghost). Reject confirm dialog. Success toast + navigate back.
  8. Confirm E2E gate GREEN.
  9. Commit `adp/04 phase-p1: 3 seller screens live-bind` qua adp-checkpoint.sh.
AMENDED 2026-07-17 (Wyatt tại ANCHOR P1, 3 quyết định):
  - ALLOWED_FILES thêm `web/src/App.tsx` + `web/src/App.css`. Lý do: glue tối thiểu không tránh được — không sửa App.tsx thì 3 screens không bao giờ render (không có gì wire chúng vào `#root`). Spec viết thiếu, không phải executor vượt rào.
  - Step 2 ("mount `api.inbox` dưới `/api`") đã được P0 làm mất — brief P0 bảo mount. Hệ quả: 3 test đầu của `test_inbox_ui_e2e.py` GREEN ngay, KHÔNG RED được. TDD discipline không thoả ở phase này; Wyatt accept vì DoD §2.5 chỉ yêu cầu backend flow (đã đạt), GĐ0.5 = local demo.
  - Intent badge: xem §3 B.2 AMENDED (Astronixa không có semantic palette).
DEBT (Wyatt accept, spec riêng): React screens hiện **0% test coverage** — GATE này chỉ khoá HTTP contract mà screens bind vào, không khoá rendering/click-through. Xoá sạch `web/src/screens/*.tsx` thì GATE vẫn xanh. FE test harness (Vitest+RTL hoặc Playwright) = spec riêng; cần dep mới + config mới nên không nhét vào P1. Tới đó: Wyatt/Tân smoke browser thủ công theo §10 PC6 trước merge.
ALLOWED_FILES: web/src/screens/*, web/src/lib/*, web/src/App.tsx, web/src/App.css, app/main.py (mount only), tests/test_inbox_ui_e2e.py
GATE: .venv/bin/python -m pytest tests/test_inbox_ui_e2e.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_web_scaffold.py tests/test_inbox_ui_e2e.py tests/test_tenant_isolation.py tests/test_policy_gate.py tests/test_orchestrator.py -x -q
RETRY: 0/3
RISK: medium
REVIEW: PASS ref=docs/reviews/04-Task-OhanaAISeller-GD0_5-InboxUI-phase-P1.json
<!-- /ADP -->

### Phase P2 — Admin wiki ingest UI

<!-- ADP:PHASE P2 -->
STATUS: IN_PROGRESS
GOAL: `/admin/wiki` page render form → POST `/api/admin/wiki/ingest` → chunks count feedback. Guard role=admin.
APPROACH:
  1. TDD gate: `tests/test_admin_ui.py` với 2 test: (a) GET `/api/admin/wiki/ingest` với non-admin cookie → 403, (b) POST với admin cookie + valid text → 200 + `chunks > 0`. Confirm RED.
  2. `auth/identity.py`: thêm `require_admin(identity) -> None` raise HTTPException(403) nếu `identity.role != "admin"`.
  3. `api/admin.py`: EDIT — thêm Depends(require_admin). Mount router under `/api` prefix trong `app/main.py`.
  4. `api/mock_auth.py`: EDIT — thêm query param `?role=admin` để dev-only mint admin cookie.
  5. `web/src/screens/AdminWikiIngest.tsx`: form với 2 field + submit button. Show `chunks: N` on success. Error toast on fail.
  6. Confirm gate GREEN.
  7. Commit `adp/04 phase-p2: admin wiki ingest UI` qua adp-checkpoint.sh.
ALLOWED_FILES: web/src/screens/AdminWikiIngest.tsx, web/src/App.tsx, web/src/App.css, web/src/lib/api.ts (edit), api/admin.py (edit), api/mock_auth.py (edit), auth/identity.py (edit), app/main.py (mount only), tests/test_admin_ui.py, tests/test_inbox_ui_e2e.py (lint-only)
GATE: .venv/bin/python -m pytest tests/test_admin_ui.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -x -q -m 'not live'
RETRY: 0/3
RISK: medium
REVIEW: PASS ref=docs/reviews/04-Task-OhanaAISeller-GD0_5-InboxUI-phase-P2.json
AMENDED 2026-07-17 (tại ANCHOR P2):
  - RISK low → **medium**: floor rule v1.3 (ALLOWED_FILES ∩ RISK_PATHS ≠ ∅). `auth/identity.py` khớp `auth/` trong manifest RISK_PATHS → floor = medium. Spec gốc propose `low` là SAI (spec-gen rule: overlap ⇒ propose tối thiểu medium). Nâng tier, không hạ — hạ mới cần RISK_WAIVER của Wyatt. Thực chất: P2 thêm `require_admin()` (auth logic thật) + mount `api/admin.py` (guard sai = unauth wiki ingest) → medium đúng bản chất, không chỉ đúng hình thức.
  - ALLOWED_FILES thêm `web/src/App.tsx` + `web/src/App.css` — cùng lý do P1 (glue để wire màn mới vào shell). Xem §7 P1 AMENDED.
  - ALLOWED_FILES thêm `app/main.py (mount only)` — step 3 của CHÍNH block này bảo "Mount router under `/api` prefix trong `app/main.py`" nhưng ALLOWED_FILES lại quên liệt kê (P1 nhớ, P2 sót). Spec tự mâu thuẫn; sửa spec cho khớp bước của chính nó.
  - ALLOWED_FILES thêm `tests/test_inbox_ui_e2e.py (lint-only)` — main session sửa 1 dòng E501 (dòng `delete(...)` quá 100 ký tự) lọt từ P1. Reviewer bắt đúng là vượt scope. Giữ fix thay vì revert vì: lint error đó ĐÃ ship ở commit P1 (`b557e53`) do GATE là pytest chứ không phải ruff — revert = cố ý để lại repo đỏ ruff. Giới hạn rõ "lint-only": KHÔNG đổi assert/logic nào.
<!-- /ADP -->

---

## §8 — DB Changes

**N/A** — không thay đổi schema. Sử dụng `PendingReply` table (Alembic 0002 từ spec 01 Phase 5).

---

## §9 — i18n

**GĐ0.5:** Vietnamese-only, hardcoded trong component (mockup pattern). Không dùng i18n framework.

Rationale: Ohana Seller VN market only. Multi-language = defer khi TAM > 1 nước (không có timeline). Thêm i18n sớm = premature complexity.

Nếu Wyatt override → dùng `react-i18next` (Vite/Next) hoặc `Flask-Babel` (Jinja) trong spec riêng.

---

## §10 — Post-checks

> Chạy SAU khi execute steps. Paste output. Tất cả PASS trước khi commit.

```bash
# PC1. Anthropic/OpenAI key NOT trong client bundle
find web/dist -type f \( -name '*.js' -o -name '*.html' -o -name '*.json' \) 2>/dev/null | xargs grep -l "sk-ant-\|sk-proj-\|ANTHROPIC_API_KEY\|OPENAI_API_KEY" 2>/dev/null
# Expected: zero hits
# Red flag: any hit → CRITICAL security bug, rollback + fix env config

# PC2. shop_id NOT hardcoded trong client
grep -rE "shop_id\s*[:=]\s*['\"]" web/src/ 2>/dev/null | grep -v "// backend derives" | grep -v "PLATFORM_SHOP_ID"
# Expected: zero hits (mọi shop_id do backend derive từ JWT)
# Red flag: hardcoded → vi phạm tenant-first invariant

# PC3. Gate suite PASS
.venv/bin/python -m pytest tests/ -x -q -m 'not live'
# Expected: all green (spec 01 baseline 17 tests + 3 spec 04 tests = 20 tests)

# PC4. Endpoint contract chưa broken
.venv/bin/python -m pytest tests/test_tenant_isolation.py tests/test_policy_gate.py tests/test_orchestrator.py -x -q
# Expected: 12/12 pass — spec 01 gates chưa regress

# PC5. Client build size reasonable
du -sh web/dist 2>/dev/null || du -sh web/static 2>/dev/null
# Expected: < 500KB gzip (React app đơn giản — nếu > 2MB thì có bloat)

# PC6. Manual smoke (Wyatt review)
# [ ] GET / → channel picker render, chỉ Zalo actionable
# [ ] Click Zalo → authorize screen → click "Cho phép & kết nối" → landed inbox (empty state)
# [ ] Seed 1 fixture PendingReply (script `.venv/bin/python -m tests.seed_pending 1`) → refresh → 1 row visible
# [ ] Click row → review card render với draft_text + 2 nút
# [ ] Click Duyệt → toast success → back inbox → row status = "approved"
# [ ] Click Từ chối trên row khác → confirm dialog → confirm → status = "rejected"
# [ ] Console: no JS errors, no CSP violations

# PC7. Grep verify callClaude NOT trong client
grep -rn "api.anthropic.com\|callClaude\|@anthropic-ai/sdk" web/src/ 2>/dev/null
# Expected: zero hits (backend orchestrator soạn draft, client chỉ render)

# PC8. CSRF token present trên state-mutating requests
grep -rE "fetch\(.*\/api\/inbox\/.*\/(approve|reject)" web/src/ | grep -v "X-CSRF-Token"
# Expected: zero hits (mọi POST approve/reject phải include CSRF header)
```

---

## §11 — Deliverables

**Files created:**
- `web/` — subdir toàn bộ (depend U1)
- `web/src/screens/ChannelPicker.tsx` (or equiv)
- `web/src/screens/Inbox.tsx`
- `web/src/screens/ReviewCard.tsx`
- `web/src/screens/AdminWikiIngest.tsx`
- `web/src/lib/api.ts`
- `web/src/lib/tokens.ts`
- `api/mock_auth.py`
- `tests/test_web_scaffold.py`
- `tests/test_inbox_ui_e2e.py`
- `tests/test_admin_ui.py`
- `docs/decisions/DEC-OHANA-01-web-framework.md`

**Files modified:**
- `app/main.py` (mount static + `/api` prefix + CSRF middleware)
- `auth/identity.py` (cookie helper + require_admin)
- `api/admin.py` (require_admin dep + mount under /api)
- `api/inbox.py` (không edit — chỉ dùng qua mount)
- `pyproject.toml` (nếu cần itsdangerous / starlette-csrf)

**Routes affected (new):**
- `GET /` → channel picker (SSR hoặc SPA shell)
- `GET /inbox` → inbox screen (SPA route)
- `GET /inbox/:id` → review card
- `GET /admin/wiki` → ingest form
- `POST /api/mock/authorize` (dev-only) — mint dev cookie
- `POST /api/mock/authorize?role=admin` (dev-only) — mint admin cookie
- `GET /api/inbox` (mount existing router under /api)
- `POST /api/inbox/{id}/approve`
- `POST /api/inbox/{id}/reject`
- `POST /api/admin/wiki/ingest` (mount existing router under /api, +require_admin)

**Commit message drafts** (do NOT commit — Wyatt review từng phase):

```
adp/04 phase-p0: web/ scaffold + cookie auth + mock authorize

Wyatt-locked framework via DEC-OHANA-01. Scaffold web/ subdir với chosen
build tool. auth/identity.py mở rộng httpOnly cookie derive + CSRF middleware
cho browser flow. api/mock_auth.py dev-only endpoint mint fixture cookie
(guard settings.env != "dev" → 404).

Refs: docs/tasks/04-Task-OhanaAISeller-GD0_5-InboxUI.md phase P0
```

```
adp/04 phase-p1: 3 seller screens live-bind

Channel picker (Zalo-only actionable), inbox list (poll 10s, GET /api/inbox),
review card (approve/reject wire). Design tokens frozen từ mockup per DEC-OHANA-01.
E2E test draft→approve→status flip PASS.

Refs: docs/tasks/04-Task-OhanaAISeller-GD0_5-InboxUI.md phase P1
```

```
adp/04 phase-p2: admin wiki ingest UI

/admin/wiki form → POST /api/admin/wiki/ingest với require_admin dep.
Mock cookie ?role=admin cho dev.

Refs: docs/tasks/04-Task-OhanaAISeller-GD0_5-InboxUI.md phase P2
```

---

## §12 — Constraints

- ONE concern per commit — 3 commits qua adp-checkpoint.sh, không gộp.
- STOP+WAIT sau mỗi phase — Wyatt review diff trước khi advance (RISK:medium = 1 confirm tại ANCHOR, RISK:low = auto-advance).
- KHÔNG copy `callClaude()` từ mockup — backend orchestrator đã soạn draft.
- KHÔNG hardcode `shop_id` trong client — backend derive từ JWT (spec 01 Phase 2 invariant, R1.22).
- KHÔNG expose Anthropic/OpenAI API key trong client bundle — post-check §10 PC1 enforce.
- KHÔNG mount `/api/mock/authorize` khi `settings.env != "dev"` — hardcode guard, không lấy từ env var (bypass risk).
- KHÔNG skip pre-flight PF6 (Wyatt lock U1) — không có DEC-OHANA-01 = không có framework quyết định.
- KHÔNG edit `agent/orchestrator.py`, `agent/policy_gate.py`, `tools/registry.py`, `bridge/`, `db/migrations/` (spec 01 Phase 5 close-out — không regress).
- KHÔNG dùng SSE/websocket ở GĐ0.5 — polling 10s đủ. SSE spec §12 note "chưa xác nhận".
- KHÔNG add real seller login (magic link / OAuth) — dev cookie fixture đủ GĐ0.5. Real login = spec 05+.
- KHÔNG add order/payment/analytics/plans screens — cắt hết per §3 Out of scope.
- KHÔNG tick DONE thủ công — chỉ qua `bash .claude/tools/adp-checkpoint.sh` (spine quyết per ADP v2.3).

---

## §13 — Tracking

| Phase | Step | Concern | STATUS | Commit | Notes |
|---|---|---|---|---|---|
| P0 | 1 | Wyatt lock U1–U4 via DEC-OHANA-01 | [ ] Pending | — | Blocking — không có = STOP |
| P0 | 2 | Gate test `test_web_scaffold.py` RED | [ ] Pending | — | TDD |
| P0 | 3 | `web/` scaffold + `app/main.py` mount | [ ] Pending | — | — |
| P0 | 4 | Cookie auth + CSRF middleware | [ ] Pending | — | RISK:medium — auth surface broaden |
| P0 | 5 | `api/mock_auth.py` dev-only | [ ] Pending | — | Guard env |
| P0 | 6 | Gate GREEN + checkpoint | [ ] Pending | — | adp-checkpoint.sh |
| P1 | 7 | Gate test `test_inbox_ui_e2e.py` RED | [ ] Pending | — | TDD |
| P1 | 8 | Mount `/api/*` prefix + collision check | [ ] Pending | — | — |
| P1 | 9 | `api.ts` client + tokens freeze | [ ] Pending | — | Depend U2 |
| P1 | 10 | 3 screens (channel/inbox/review) | [ ] Pending | — | Port UX từ mockup |
| P1 | 11 | Gate GREEN + checkpoint | [ ] Pending | — | adp-checkpoint.sh |
| P2 | 12 | Gate test `test_admin_ui.py` RED | [ ] Pending | — | TDD |
| P2 | 13 | `require_admin` + admin cookie flag | [ ] Pending | — | — |
| P2 | 14 | Admin ingest form + mount | [ ] Pending | — | — |
| P2 | 15 | Gate GREEN + checkpoint | [ ] Pending | — | adp-checkpoint.sh |
| — | — | Post-checks §10 all PASS | [ ] Pending | — | Wyatt manual smoke |
| — | — | Merge `feat/gd0_5-inbox-ui` → main | [ ] Pending | — | Sau Wyatt review |

---

## §14 — Open Questions (RESOLVED via DEC-OHANA-01, 2026-07-17)

✅ Tất cả 5 U-questions đã Wyatt-signed trong [DEC-OHANA-01-web-framework.md](../decisions/DEC-OHANA-01-web-framework.md). PF6 gate PASS. P0 unblocked.

**Quick summary (authoritative source = DEC-OHANA-01):**
- **U1** → Vite + React SPA, serve `web/dist/` qua FastAPI, API mount dưới `/api` prefix.
- **U2** → Astronixa "OHANA" Design System từ Figma `JRoD28RIxiEfSEgVqDZLNJ` (6 color palettes × 10 shades, Inter typography, 3-stop gradient CTA, 4-tab bottom nav pill, toast). Component reuse policy: chỉ primitives (colors/typography/buttons/toast/nav-base), KHÔNG reuse feature components của Ohana Social super-app (chat/video/meeting/newsfeed). Executor pull component code qua Figma MCP tại implementation time. Chi tiết bảng tokens trong DEC-OHANA-01 §U2.
- **U3** → Local dev only (localhost:8000). SameSite=Lax cookie. Staging = spec 06.
- **U4** → Dev cookie fixture qua `POST /api/mock/authorize` (guard `settings.env == "dev"`). Real login = spec 05.
- **U5** → Cắt conversation history ở GĐ0.5. Review card render `draft_text` + intent + confidence + status. Add sau ở spec 05.

**RISK finalized:** P0=medium, P1=medium, P2=low. No RISK_WAIVER.

### U1 — Framework choice cho `web/`

**Options + tradeoffs:**

| Option | Pro | Con | Fit mockup port |
|---|---|---|---|
| **Vite + React SPA** (recommended) | Nhẹ, dev fast, mockup port ~as-is (cùng React), static bundle serve qua FastAPI, không cần Node runtime prod | Không SSR (không cần cho seller-facing tool), 2 build system (Python + Node) | ★★★★★ trực tiếp |
| Next.js 14 App Router | SSR nếu cần SEO/OG, RSC pattern hiện đại | Overhead lớn cho GĐ0.5 (seller-facing, không SEO), cần Node runtime prod, thêm complexity | ★★★★ |
| FastAPI + Jinja + HTMX | Single-repo, không build step, không Node | Vứt bỏ toàn bộ mockup React, Wyatt/Tân re-learn HTMX pattern, animation/state complex hơn | ★★ |

**Recommendation:** Vite + React SPA. Rationale: (a) mockup đã React, tận dụng được, (b) GĐ0.5 không cần SSR, (c) build output static bytes serve qua FastAPI = 1 process prod.

**Answer:** _____ (Wyatt fill)

### U2 — Brand kit source

- Option A: Adapt từ mockup (freeze tokens: `#4F46E5→#7C3AED` gradient, mobile 410×800 shell, Inter/system-ui, lucide-react icons).
- Option B: Xin từ Tân/Astronixa (parent brand Astronixa Ohana có identity guide riêng).

**Recommendation:** Ping Tân trước — nếu có kit chính thức thì dùng (align brand ecosystem). Không → Option A (freeze mockup).

**Answer:** _____ (Wyatt fill)

### U3 — Deploy target GĐ0.5

- Option A: Local dev only (localhost:8000). Không CORS issue.
- Option B: Staging URL (ví dụ `staging.ohana-seller.local` hoặc VPS). Cần config CORS + cookie SameSite/Secure.

**Recommendation:** Option A cho GĐ0.5 (Wyatt/Tân demo local). Staging = spec 06 khi có real Zalo OA creds.

**Answer:** _____ (Wyatt fill)

### U4 — JWT issuance cho seller login

- Option A: Dev cookie fixture qua `POST /api/mock/authorize` — mint JWT với `(user_id="dev-user", shop_id="fixture-shop-001", role="seller")`. Real login = spec sau.
- Option B: Magic link email (send-blocking mà `enabled=False` như Zalo).
- Option C: `POST /auth/login` với email+password (cần user table + hashing).

**Recommendation:** Option A cho GĐ0.5. Real seller login = spec 05 song song với PRE-004 backfill (khi có real Zalo, mới có real seller accounts).

**Answer:** _____ (Wyatt fill)

### U5 — Conversation history endpoint (nice-to-have)

Review card mockup hiện conversation context. Backend chưa có `GET /conversations/{id}/messages`. Options:

- Option A: Cắt conversation context ở GĐ0.5 — review card chỉ hiển thị `draft_text` + intent + confidence.
- Option B: Add `GET /api/inbox/{id}/context` endpoint (trả last-N inbound messages đến `customer_id`).

**Recommendation:** Option A. Option B add trong spec 05 (cùng với real Zalo webhook — lúc đó có real inbound messages để hiển thị).

**Answer:** _____ (Wyatt fill)

---

*End of spec 04. Ohana ADP v2.3. Waiting Wyatt lock U1–U4 (+ optional U5) trong DEC-OHANA-01 trước khi execute P0.*
