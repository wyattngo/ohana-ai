# DEC-OHANA-01 — `web/` Framework + GĐ0.5 UI Foundation

**Status:** ACCEPTED
**Date:** 2026-07-17
**Signed by:** Wyatt Ngo (Approver, A per ADP v2.3)
**Author:** Claude Opus 4.7 (recommendation) · Wyatt Ngo (approval)
**Spec unlocked:** [04-Task-OhanaAISeller-GD0_5-InboxUI.md](../tasks/04-Task-OhanaAISeller-GD0_5-InboxUI.md)
**Supersedes:** Spec 01 §12 `[UNVERIFIED] web/` note

---

## Context

Spec 01 (GĐ0 MVP) shipped 5 HTTP endpoints (`GET /inbox`, `POST /inbox/:id/approve|reject`, `POST /admin/wiki/ingest`, `POST /webhook/zalo/:oa_id`) nhưng chưa có UI. Spec 01 §12 marked `web/` framework choice là [UNVERIFIED] — defer sang spec 04 (GĐ0.5).

Spec 04 khoá 5 open questions (U1–U5) block P0 execution. Wyatt review spec 04 draft 2026-07-17 và approve toàn bộ recommendations của Claude. DEC này lock từng decision để adp-checkpoint.sh PF6 gate PASS.

---

## Decisions

### U1 — Framework: **Vite + React SPA**

Serve static bundle (`web/dist/`) qua FastAPI `app.main`. Single-process production. Client-only routing (react-router-dom).

**Rationale:**
- Mockup `~/Downloads/seller_ai_copilot_demo.jsx` đã React → port ~as-is (design tokens + screen shapes reuse trực tiếp).
- Seller-facing tool → không cần SEO → không cần SSR → Next.js overhead không justify.
- Vite dev server hot-reload = fast iteration cho GĐ0.5.
- Prod deploy = 1 process (FastAPI serve API + static) → matches CLAUDE.md "small safe patches" preference.

**Rejected:**
- Next.js 14 App Router — overhead lớn cho tool nội bộ không SEO, cần Node runtime prod (2 process), RSC pattern học phí.
- FastAPI + Jinja + HTMX — vứt bỏ toàn bộ React knowledge trong mockup, animation/state phức tạp hơn khi có polling + optimistic updates.

**Constraints:**
- Node >= 20, pnpm (không dùng npm/yarn — pnpm nhanh + lockfile chuẩn).
- Build output `web/dist/` mount ở `/` trong `app/main.py` qua `StaticFiles`.
- API mount dưới prefix `/api` để tránh collision với SPA routes.
- Tất cả CSP inline (no CDN) — matches CLAUDE.md path safety.

---

### U2 — Brand kit: **Astronixa "OHANA" Design System (Figma)**

**Source (authoritative):** Figma file `JRoD28RIxiEfSEgVqDZLNJ` — "OHANA (Copy)", page `system` (id 0:1). Wyatt-shared 2026-07-17.

**Access:** Wyatt Figma account có edit permission trên copy này → Dev Mode MCP endpoints (`get_metadata`, `get_design_context`, `get_variable_defs`, `get_screenshot`) all working. Executor session sẽ pull component code trực tiếp từ Figma qua `get_design_context(nodeId=...)` cho từng screen — KHÔNG hardcode component markup vào DEC.

**Overview screenshot:** [`assets/ohana-figma-overview.png`](assets/ohana-figma-overview.png) (127KB, 1600×578 preview) — committed vào repo cho persistence. Figma asset URL gốc expire sau 7 ngày; live re-pull qua `get_screenshot(fileKey='JRoD28RIxiEfSEgVqDZLNJ', nodeId='0:1')`.

**Frozen tokens (source: Figma canvas `0:1` metadata + `get_design_context` cho components 4008:3157 button, 4034:1270 bottom-nav, 4018:7518 toast):**

**Color palettes** (10-shade families — 50/100/200/300/400/500/600/700/800/900):

| Family | 50 | 100 | 200 | 300 | 400 | **500 (base)** | 600 | 700 | 800 | 900 |
|---|---|---|---|---|---|---|---|---|---|---|
| **Primary (purple)** | `#f9f0ff` | `#f6e8ff` | `#e3bfff` | `#cd97ff` | `#b56eff` | **`#9744fb`** | `#752fd5` | `#561eaf` | `#3b1088` | `#240762` |
| **Secondary (blue)** | `#f0f6ff` | `#d6e6ff` | `#adcaff` | `#85abff` | `#5c8aff` | **`#3366ff`** | `#2148d9` | `#122fb3` | `#071b8c` | `#000c66` |
| **Tertiary (magenta)** | `#fdf0ff` | `#fdf0ff` | `#f5ccff` | `#eba3ff` | `#dd7aff` | **`#ca50fb`** | `#a339d5` | `#7e26af` | `#5c1788` | `#3e0c62` |
| **Accent (cyan)** | `#ccfff9` | `#a3fff8` | `#7afffa` | `#52fffe` | `#29faff` | **`#00f0ff`** | `#00c5d9` | `#009cb3` | `#00768c` | `#005266` |
| **Neutral** | `#beb5c1` | `#b1a9b4` | `#a49da7` | `#98919b` | `#8b858e` | **`#7c7481`** | `#554d5b` | `#302a35` | `#0d0b0e` | `#000000` |
| **Greyscale** | `#f2f2f2` | `#d2d2d2` | `#b4b4b4` | `#969696` | `#797979` | **`#5e5e5e`** | `#444444` | `#2c2c2c` | `#151515` | `#030303` |

**Signature CTA gradient (3-stop, Login button):**
`linear-gradient(to left, #2e96fe 0.17%, #9744fb 55.75%, #ca50fb 100%)`
= secondary/500 → primary/500 → tertiary/500. Rounded `100px` pill, padding `10px`, text `Inter Semibold 16px white center`.

**Toast:**
- Bg `#43038f` (deep purple — outside standard scale, treat as `primary/850` custom)
- H `80px`, padding `30px`, rounded-bottom-only `20px 20px 0 0` (drops from top)
- Text `Inter Semibold 16px white`
- Close icon 24×24 right

**Bottom nav (4-tab pill):**
- Container: `bg-primary/500 (#9744fb)`, rounded `50px`, padding `4px`
- Tab (inactive): `text-white`, no bg, `py-8px w-97px`
- Tab (active): `bg-white`, rounded `50px`, `text-primary/500`
- Icon 24×24, label `Inter Regular 12px`
- 4 tabs: `Chats | Contacts | Newfeeds | Profile` (Ohana Social taxonomy — see §Component reuse policy below)

**Typography:**
- Family: `Inter` (headline/body/label — confirmed in "Aa" preview panels)
- Weights used: Regular (400), Semibold (600) — no Light/Bold
- Sizes in components: `12px` (labels), `16px` (button text) — heading scale = pull from Figma text-styles at implementation time

**Radii:**
- Pill (buttons, tabs) = `100px`
- Nav container = `50px`
- Toast (partial) = `20px` top corners inverted (drop-from-top pattern)
- Card / row (in seller UI) = **NOT SET in Astronixa system**; propose `16px` default, subject to Wyatt tweak

**Icons:**
- Astronixa has custom icon set (78 symbols in file: `chat`, `contact`, `profile`, `bell`, `settings`, `camera`, `share`, etc.) — SVG served via `get_design_context` asset URLs.
- **For seller UI:** default `lucide-react` (94% overlap with Astronixa icon vocabulary, no Figma dep at build time). Swap to Astronixa custom icons per-icon when Wyatt requests brand fidelity (`Inbox`, `Send`, `Check`, `X` are the 4 hot icons for GĐ0.5 — assess overlap in P1 step 5).

**Theme:** file has light/dark toggle component (nodes 4126:20365 dark, 4126:20367 light, 4126:20417 Frame 94 variants) — GĐ0.5 **light mode only**. Dark mode = defer spec 05+.

**Component reuse policy (CRITICAL):**

Astronixa "OHANA" file = design system cho **Ohana Social super-app** (astronixa.us positioning: social network + messaging + HD video). Chứa components cho `chat`, `contact`, `newsfeed`, `profile`, `meeting`, `channel`, `screen-share`, `photo-album`, `keyboard`, `call controls`. **Ohana AI Seller ≠ Ohana Social** — chỉ reuse PRIMITIVES, KHÔNG reuse feature components.

| Astronixa component | Reuse cho Ohana AI Seller? |
|---|---|
| Color palettes (all 6) | ✅ Reuse toàn bộ |
| Typography (Inter + sizes) | ✅ Reuse |
| Button (3-stop gradient pill) | ✅ Reuse cho "Duyệt" primary CTA |
| Toast_Notify | ✅ Reuse cho success/error feedback |
| Bottom_navigate (4-tab pill) | ⚠️ Adapt — seller có 2 tabs (Inbox + Admin), KHÔNG có Chats/Contacts/Newfeeds/Profile |
| Button select/checkbox toggles | ✅ Reuse |
| Free/Premium account chips | ❌ Không dùng — GĐ0.5 không có plans/billing |
| Logo (OHANA wordmark, id 4021:14967) | ✅ Header của Inbox screen |
| icon logo (78×78, id 4024:2193) | ✅ Favicon + PWA icon |
| Chat / Contact / Newsfeed / Profile / Meeting / Channel components | ❌ Không reuse — khác product |
| Video / Screen-share / Camera controls | ❌ Không reuse |
| Photo Album / Photo grid | ❌ Không reuse |
| Keyboard mock | ❌ Không reuse |
| Folder picker (Frame 147) | ❌ Không reuse |

**Follow-up:** Nếu Wyatt cần seller UI có **branded feel matching astronixa.us** (dark hero + purple gradient shell), extract cho DEC-OHANA-02 sau khi P0/P1 shipped baseline. GĐ0.5 giữ light mode + tokens raw đủ để demo.

**Override rule:** Astronixa design team update tokens → executor pull lại qua Figma MCP (Vite HMR pick up), single file `web/src/lib/tokens.ts` = single point of change. Không rewrite screens.

---

### U3 — Deploy target GĐ0.5: **Local dev only (localhost:8000)**

Không staging URL, không CORS config, không HTTPS.

**Rationale:**
- GĐ0.5 = internal Wyatt+Tân demo. Chưa có seller thật cần test.
- Real Zalo webhook cần public URL — chờ PRE-004 backfill (Zalo OA creds).
- Staging = spec 06 khi PRE-004 landed, ghép chung với deploy pipeline.

**Constraints:**
- Cookie `SameSite=Lax` (mặc định browser modern) — vì same-origin (FastAPI serve both API + static).
- Nếu Wyatt cần demo remote (Tân xem qua Zoom) → dùng `ngrok http 8000` tạm, không config CORS thay đổi.

**Override rule:** Staging = spec 06. Ghi cross-ref khi tạo spec 06.

---

### U4 — JWT issuance GĐ0.5: **Dev cookie fixture qua `POST /api/mock/authorize`**

Không magic link, không email/password, không OAuth.

**Fixture claim shape:**
```json
{
  "user_id": "dev-user-001",
  "shop_id": "fixture-shop-001",
  "role": "seller"
}
```

Với query `?role=admin` → mint claim với `role="admin"` cho admin ingest screen (P2).

**Constraints:**
- `api/mock_auth.py` MUST guard `if settings.env != "dev": raise HTTPException(404)` — hardcode check, không lấy từ env var (bypass risk).
- Cookie name: `ohana_session`. httpOnly=True, Secure=False (localhost), SameSite=Lax.
- JWT algo: HS256 (match spec 01 Phase 2 auth/identity.py).
- JWT lifetime: 24h (dev convenience — không cần refresh flow ở GĐ0.5).

**Real login flow (Option B/C từ spec 04 §14 U4):** Defer sang **spec 05** — implement song song với PRE-004 (Zalo OA credentials landed → mới có real seller accounts để login).

---

### U5 — Conversation history endpoint: **Cắt ở GĐ0.5 (Option A)**

Review card chỉ hiển thị: `customer_id` (avatar+name), `draft_text` (full), `intent` badge, `confidence` bar, `status` badge.

**Không hiển thị:** lịch sử tin nhắn khách gửi.

**Rationale:**
- Backend chưa có `GET /conversations/{id}/messages` endpoint.
- GĐ0.5 = mock authorize flow → không có real inbound messages để hiển thị.
- Draft text đã đủ context cho seller quyết định approve/reject (orchestrator đã include context lúc soạn).

**Follow-up:** Spec 05 add `GET /api/inbox/{id}/context` cùng với real Zalo webhook enable — lúc đó có real messages.

---

### RISK tier finalization

Wyatt confirm proposed tiers:

| Phase | RISK | Rationale |
|---|---|---|
| P0 | **medium** | `auth/identity.py` broaden trust surface (cookie derive) + CSRF middleware — chạm auth contract nhưng không chạm decision logic. |
| P1 | **medium** | `app/main.py` mount `/api` prefix + client bind → nếu sai = mọi endpoint down. E2E test = gate. |
| P2 | **low** | Admin-only, không customer-facing, không chạm RISK_PATHS ngoài `auth/identity.py` helper mở rộng (đã cover trong P0). |

**No RISK_WAIVER needed** — không có phase nào propose low với RISK_PATHS overlap.

**Autonomy per tier (ADP v2.3 DEC-019 semantic áp dụng cho Ohana):**
- P0/P1 (medium): 1 confirm tại ANCHOR + reviewer gate + auto-checkpoint + async REVIEW_QUEUE.md
- P2 (low): full auto-flow + auto-advance sang phase low kế tiếp (không có phase low kế tiếp — kết thúc spec)

---

## Impact / Consequences

**Positive:**
- P0 execution unblocked — spec 04 PF6 gate sẽ PASS khi thấy file này.
- Framework decision reversible — Vite → Next migration = single-file change (`vite.config` → `next.config`) + component moves, không rewrite logic.
- Design tokens single-file = swap brand kit sau này không rewrite screens.

**Negative / Risks:**
- Node build system add complexity — thêm 1 build step (pnpm install + vite build) vào CI. Cần document trong `README.md` sau P0.
- CSRF middleware chưa có trong Ohana codebase — cần import mới (`itsdangerous` hoặc `starlette-csrf`). Add dep trong `pyproject.toml` step P0.
- Dev cookie fixture = security debt — MUST remove trước khi staging (spec 06 gate).
- Cắt conversation history = review card sparse ở GĐ0.5 — Wyatt/Tân demo có thể feel "thiếu" nhưng đúng scope.

**Reversibility:** 
- U1 (framework): 2–3 ngày rewrite nếu chuyển Vite → Next hoặc HTMX.
- U2 (tokens): trivial, 1 file swap.
- U3 (local only): non-decision, tự nhiên upgrade lên staging.
- U4 (dev cookie): MUST remove trước staging = hard-block ở spec 06 gate.
- U5 (no conversation history): trivial add sau.

---

## Follow-up actions

- [ ] Wyatt ping Tân về Astronixa brand kit (không blocking P0).
- [ ] Session sau invoke `drnick-coder` để execute P0 với DEC này làm input.
- [ ] Spec 05 (real login flow) — schedule khi PRE-004 backfill có timeline.
- [ ] Spec 06 (staging deploy) — schedule khi PRE-004 landed.

---

*DEC-OHANA-01. ADP v2.3. Wyatt-signed 2026-07-17. Do not amend — supersede via new DEC-OHANA-NN if needed.*
