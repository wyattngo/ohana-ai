# CLAUDE.md — Ohana AI Seller (project router)

> **Sub-project của workspace `localhost/`.** Router level 0 tại `../CLAUDE.md`.
> Owner: Tân (dev lead) · Approver: Wyatt Ngo (fractional CTO)
> Last updated: 2026-07-18 · Status: **SPEC 01 + 04 + 05 = 100% DONE** — F1 wiki-RAG pipeline + `OpenAIEmbedder` thật đã wire (spec 05) nhưng ⚠️ **chưa nghiệm thu live** (DoD #5 chờ `pytest -m live` real key — ISSUE-016 vẫn OPEN) + F2 API Q&A (mock endpoints) + F3 policy-gate/pending_reply + seller UI 4 màn (Vite SPA, Wyatt smoke browser OK). PRE-002/003/004 backfill deferred until source landed.

---

## 1. Định danh

| Field | Value |
|---|---|
| Project | Ohana AI Seller (GĐ0 MVP) |
| Kind | AI copilot cho seller social-commerce VN (Zalo/FB/IG) |
| Stack (backend) | Python 3.11 / FastAPI / PostgreSQL + pgvector / Alembic — **fork chọn lọc từ `drnickv4/`**. Redis chưa wire (Phase 3+). |
| Stack (web/) | Vite 8 + React 19 + TypeScript + pnpm + lucide-react (spec 04 / DEC-OHANA-01 §U1). **Node ≥ 20 bắt buộc** — system default trên máy Wyatt là v16, dùng `nvm use v23.6.1` trước mọi lệnh pnpm. Build: `cd web && pnpm install && pnpm build` → `web/dist/` (committed, chưa có CI Node step). |
| Repo | `ohana-ai` (init) — branch `main`, phases 1–5 shipped, no remote configured |
| Duration | 3–4 tuần, Zalo-only |
| Priority order | safety → user trust → stability → growth (KHÔNG dùng fintech Survival Framework) |
| Parent workspace | `/Users/wyattngo/Sites/localhost/` |

---

## 2. Trạng thái hiện tại

- ✅ **Spec 01 (5/5)** · ✅ **02 (4/4)** · ✅ **04 (3/3)** · ✅ **05 (3/3)** · ✅ **06 Foundation (3/3)** · ⏳ Spec 03 = 0/10 (4 BLOCKED). **Overall ADP 18/28 phase gate-passed (64%)** — dashboard: `bash .claude/tools/adp-status.sh`.
- Spec canonical: `docs/tasks/01-Task-OhanaAISeller-GD0.md` (GĐ0 backend) + `docs/tasks/04-Task-OhanaAISeller-GD0_5-InboxUI.md` (GĐ0.5 UI). Mọi phase block DONE đều có EVIDENCE stamped.
- Latest STATE_HASH: `edb8b40d651e` @ spec 06 phase-F2 close (2026-07-18).
- `main` — spec 04 + 05 merged; **spec 06 commit THẲNG trên `main`** (6 commit, ahead origin/main). ⚠️ Spec 06 §0 header khai `Branch: adp/06-foundation` — **không đúng thực tế**, branch đó chưa từng được tạo. **Chưa push** origin (Wyatt chạy tay).
- Test suite: **69 test, 1 xfail** (`.venv/bin/python -m pytest tests/ -m 'not live'`), ruff sạch, **mypy 0 lỗi** (spec 06 F2 đưa từ 12 → 0; trước đó CI mypy ĐỎ âm thầm trên main). `xfail` = `OpenAIClient` chưa import được (`app/alert_service.py` chưa port — ISSUE-010).
- `tests/conftest.py` cung cấp fixture `fresh_db` (drop+create schema, dispose kể cả khi test raise) — test DB mới dùng nó, KHÔNG tự dựng engine.
- **Shipped surface — Foundation (spec 06, 2026-07-18) — vá nền móng Spec 03 đang đứng trên:**
  - F0 (high) — `db/models.py` thêm `Customer` / `Conversation` / `OrderDraft` tenant-first + Alembic `0003`. **Composite FK `(shop_id, <child_id>)`** → Postgres TỪ CHỐI row shop A trỏ row shop B (FK đơn không chặn được điều đó). FK hoá 2 cột mồ côi `PendingReply.conversation_id/customer_id`. `ConversationRepo` theo pattern `_shop_scope`. Identity type = **TEXT** (PRE-F01 Wyatt ký — KHÔNG migrate sang UUID).
  - F1 (medium) — `channels/{base,identity}.py` + `channels/zalo/`; `api/webhook.py` viết lại generic `/webhook/{channel}/{external_id}` (**VẪN chưa mount**). **Gỡ shim `conversation_id or customer_id`** ở `agent/orchestrator.py` → `conversation_id` là tham số BẮT BUỘC; identity mapping `(channel, external_user_id) → (customer_id, conversation_id)` nằm ở channel layer.
  - F2 (medium, nâng từ low theo floor rule) — `tests/conftest.py` (ĐÓNG ISSUE-014) + **mypy 12→0** (`identity_dep`/`admin_dep` từ `object` → `Callable[..., Identity]`, `_session() -> AsyncIterator`, cast `CursorResult`). ci.yml mypy scope += `db bridge tools`.
  - ⚠️ **NỢ: `channels/identity.py` thiếu unique `(shop_id, customer_id, channel)`** → race có thể tạo 2 Conversation. Vô hại vì webhook chưa mount; **PHẢI thêm constraint trước khi Spec 03c mount webhook** (ISSUE-017).
- **Shipped surface — Config + Embedder thật (spec 05, 2026-07-18):**
  - P0 (medium) — `app/config.py` `Settings(BaseSettings)` + `get_settings()` lru_cache (4 field: `openai_api_key`, `openai_embed_model="text-embedding-3-small"` 1536-dim, `openai_model`, `reasoning_models`). `OpenAIEmbedder` hết `ModuleNotFoundError`. gate `test_config.py`.
  - P1 (medium) — `api/admin.py default_embedder()` env-selecting: key→`OpenAIEmbedder` thật; no-key→`_DeterministicDevEmbedder` (raise-outside-dev ở `embed()`, KHÔNG ở factory — vì `app/main.py` gọi lúc import). gate `test_embedder_wiring.py` (offline, inject fake client) + `test_wiki_rag_live.py` (`@pytest.mark.live`, DoD #5).
  - P2 (medium) — `get_jwt_secret()` + `db/session.py get_database_url()` đọc qua `Settings()` **fresh mỗi call** (KHÔNG `get_settings()` cached — né cache-staleness trên security path). Fail-closed byte-identical.
  - ⚠️ **ISSUE-016 vẫn OPEN — và đã ĐỔI BẢN CHẤT**: ADR `docs/adr/2026-07-18-hosting-region.md` chốt provider = **Together AI open-weight**, embedding chuyển `text-embedding-3-small` (1536) → `intfloat/multilingual-e5-large-instruct` (**1024-dim**). Nghĩa là live acceptance phải chạy trên **e5, KHÔNG phải OpenAI**, và cần migration đổi dim `Vector(1536)` + re-embed corpus. ADR vẫn **PROPOSED** (chờ Wyatt chốt deployment-region + legal).
- **Shipped surface — GĐ0.5 UI (spec 04, 2026-07-17):**
  - P0 (medium) — `web/` Vite+React+TS scaffold, `web/src/lib/tokens.ts` (Astronixa tokens frozen), `auth/identity.py identity_from_cookie()` + `get_jwt_secret()` fail-closed, CSRF double-submit middleware trong `app/main.py`, `api/mock_auth.py` `POST /api/mock/authorize` (dev-only, `?role=admin`), gate `test_web_scaffold.py` 6/6.
  - P1 (medium) — 3 màn seller `web/src/screens/{ChannelPicker,Inbox,ReviewCard}.tsx` + `web/src/lib/api.ts` (CSRF tập trung trong `apiFetch`), state-based routing (KHÔNG react-router), gate `test_inbox_ui_e2e.py` 4/4. **Wyatt smoke browser xác nhận chạy thật.**
  - P2 (medium — nâng từ low theo floor rule vì chạm `auth/`) — `auth/identity.py require_admin()`, `api/admin.py` guard + mount (trước đó route này KHÔNG xác thực), `web/src/screens/AdminWikiIngest.tsx`, gate `test_admin_ui.py` 4/4.
  - Routes mounted trong `app/main.py`: `/api/inbox` (3), `/api/mock/authorize` (dev-only), `/api/admin/wiki/ingest` (require_admin), `StaticFiles(web/dist)` ở `/` **mount CUỐI** (catch-all — mount trước sẽ che `/api/*`). `api/webhook.py` **vẫn chưa mount** (thiếu concrete `Drafter` impl).
  - Design system: Astronixa "OHANA" Figma `JRoD28RIxiEfSEgVqDZLNJ` — 6 palette × 10 shade, Inter, CTA gradient 3-stop. **KHÔNG có semantic palette** (danger/warning/success) → intent badge dùng icon + label VI, xem DEC-OHANA-01 §U2.
- **Shipped surface — GĐ0 backend (spec 01):**
  - Phase 2 (RISK:high) — `auth/identity.py` HS256, `db/{models,session,repos}.py` tenant-first + Alembic 0001, `retrieval/pgvector.py PgvectorRetriever(shop_scope=)` SQL-level hard filter, gate `tests/test_tenant_isolation.py` 3/3.
  - Phase 3 (low) — `parsing/{chunk,ingest}.py`, `tools/{registry,wiki}.py`, `api/admin.py` ingest, gate `test_wiki_rag.py` 2/2 (happy + adversarial ns iso). Gate deterministic chạy bằng `FakeEmbedder` inline. **Spec 05 đã wire `OpenAIEmbedder` thật** (`app/config.py` landed, `default_embedder()` env-selecting) — nhưng ⚠️ **F1 chưa nghiệm thu với embedding thật**: DoD #5 (`tests/test_wiki_rag_live.py -m live`, real OPENAI_API_KEY) chờ Wyatt/Tân chạy tay. **ISSUE-016 (high) vẫn OPEN** cho tới lúc đó — code-complete ≠ F1-verified.
  - Phase 4 (medium) — `bridge/ohana_client.py` R1.1-extended REST client (verify=True hardcoded), `tools/ohana_read.py order_status`, gate `test_ohana_tools.py` 10/10 (MockTransport).
  - Phase 5 (RISK:high) — `agent/{policy_gate,orchestrator}.py`, `db/models.py PendingReply` + Alembic 0002, `bridge/zalo_sender.py MockZaloSender`, `api/{webhook,inbox}.py` scaffolds, gate `test_policy_gate + test_orchestrator + test_tenant_isolation` 12/12.
- **Blocking backfill (không chặn gate — chặn real-endpoint content):**
  - PRE-002 — real Ohana platform API endpoint spec chưa từ Tân → order_status test hiện là MockTransport contract; F2 tools thứ 2/3/4 (shipping/product/account) chưa land.
  - PRE-003 — real Wiki docs corpus chưa land → ingest hoạt động, chỉ chưa có nội dung thật.
  - PRE-004 — Zalo OA creds + webhook signature + rate-limit spec chưa từ Tân → webhook `enabled=False` default, `MockZaloSender` thay real sender, send-on-approve worker chưa wire.
- Cleared: PRE-001 (drnickv4/db/models.py đọc + tenant-first design landed Phase 2), PRE-005 (Zalo-first confirmed by Wyatt lock in 2026-07-16 spec approval), PRE-006 (`shop_id` alone confirmed sufficient qua tất cả Phase 2 tests).

---

## 3. Nguồn port (đọc trước khi build)

**KHÔNG fork nguyên `drnickv4/` repo.** Port chọn lọc từng module, viết mới phần multi-tenant.

| Từ `drnickv4/` | Sang `ohana-ai/` | Ghi chú |
|---|---|---|
| `agent/llm_client.py` + `providers/` | `agent/llm_client.py` + `providers/` | Reuse nguyên |
| `agent/embedder.py`, `retrieval/`, `parsing/`, `storage/` | Cùng path | Reuse — thêm `shop_id` scope SQL-level |
| `agent/orchestrator.py` | `agent/orchestrator.py` | Adapt async cho F3 pending_reply |
| `tools/registry.py` | `tools/registry.py` | Port nguyên shape Tool dataclass |
| `bridge/onfa_client.py` | `bridge/ohana_client.py` | Viết mới theo pattern REST + verify=True |
| `auth/identity.py` + `auth/jwt.py` | Cùng path | Mở rộng JWT claim `(user_id, shop_id, role)` |
| `db/models.py` | Viết lại tenant-first | **KHÔNG copy** — DrNick single-tenant |
| `.claude/hooks/guardrail.py` | Cùng path | Đổi R1.13 money → intent-safety Ohana |
| Reviewer subagent, CI workflow, Alembic skeleton, RULES/ADP | Reuse | ADP discipline giữ nguyên |

**KHÔNG port sang:** `bridge/onfa_client.py`, `tools/onfa_actions.py`, `pending_action` financial logic, ConfirmEvent 2FA path.

---

## 4. Trigger signals (routing)

Chuyển sang project này khi user nhắc:
`Ohana`, `Ohana AI`, `ohana-ai`, `Zalo OA`, `seller copilot`, `Wiki RAG`, `policy_gate`, `pending_reply`, `shop_id`, `multi-tenant`, `platform_wiki`, `GĐ0 MVP`, `Tân`.

**Skill auto-trigger:** `drnick-coder` (reuse — Plan-Patch-Verify Python/FastAPI phù hợp Ohana), `onfa-spec-generator` (nếu cần thêm spec phase), `onfa-brief-formatter` (intake brief mới).

---

## 5. ADP Manifest (v2.3 — Wyatt finalize RISK per phase)

<!-- ADP:MANIFEST -->
GATE_RUNNER: .venv/bin/python -m pytest -q -x
RISK_PATHS: agent/orchestrator.py, agent/policy_gate.py, tools/registry.py, bridge/, auth/, db/migrations, api/webhook.py, api/inbox.py, api/admin.py
SPEC_DIR: docs/tasks
EXECUTOR_SKILL: drnick-coder
CHECKPOINT_PREFIX: adp
<!-- /ADP -->

**Isolation**: Ohana AI dùng ADP v2.3 riêng (`ohana-ai/.claude/`), KHÔNG dùng workspace v1.3 của Onfa/DrNick. Sandbox: an toàn để calibrate decision-gate (SHADOW → hard-block sau ≥5 real decisions).

Xem `docs/adr/hook-contract.md` + `MODEL.md` bundle export cho contract chi tiết. Workspace router `../CLAUDE.md §4.7` mô tả v1.3 flow (áp dụng Onfa/DrNick).

---

## 6. Layout thực tế (verified 2026-07-18 sau spec 06)

```
ohana-ai/
├── CLAUDE.md              ← File này (router project)
├── pyproject.toml
├── Dockerfile
├── .env.example           Template env cho admin (secret để RỖNG — placeholder là truthy!)
├── app/                   FastAPI entrypoint
├── agent/                 orchestrator, llm_client, embedder, policy_gate (NET-NEW)
│   └── providers/         LLM providers (KHÔNG phải top-level `providers/` — sửa drift 2026-07-18)
├── channels/              Channel abstraction (spec 06 F1)
│   ├── base.py            InboundChannel / OutboundChannel Protocol
│   ├── identity.py        resolve_conversation() — (channel, external_id) → ids nội bộ
│   └── zalo/              Adapter bọc bridge/zalo_sender.py (interface giữ nguyên)
├── retrieval/             pgvector wrapper (shop_id-scoped)
├── parsing/               Wiki doc chunker
├── storage/               Storage abstractions
├── bridge/
│   └── ohana_client.py    REST client platform API
├── auth/                  identity + jwt (multi-tenant)
├── tools/
│   ├── registry.py
│   ├── wiki.py            F1 search_wiki
│   └── ohana_read.py      F2 order/shipping/product/account
├── api/
│   ├── admin.py           Wiki ingest (require_admin — spec 04 P2)
│   ├── inbox.py           Seller inbox (list/approve/reject) — KHÔNG phải chat.py
│   ├── mock_auth.py       Dev-only authorize (guard OHANA_ENV=="dev")
│   └── webhook.py         Zalo inbound (chưa mount — thiếu concrete Drafter)
├── db/
│   ├── models.py          Tenant-first (shop_id everywhere)
│   └── migrations/        Alembic
├── web/                   Seller UI — Vite 8 + React 19 + TS (DEC-OHANA-01 §U1)
│   ├── src/
│   │   ├── App.tsx          Shell + state-based screen switching (KHÔNG react-router)
│   │   ├── lib/
│   │   │   ├── api.ts       Typed client — apiFetch() bọc CSRF + credentials
│   │   │   ├── intent.ts    Intent/status badge metadata (icon + label VI)
│   │   │   └── tokens.ts    Astronixa tokens frozen → CSS vars --ohana-*
│   │   └── screens/         ChannelPicker · Inbox · ReviewCard · AdminWikiIngest
│   └── dist/              Build output — COMMITTED (chưa có CI Node step)
├── tests/
├── .claude/               (port từ drnickv4/ khi bootstrap)
└── docs/
    ├── tasks/             Spec ADP (01 GĐ0 · 02 bootstrap · 03 backfill · 04 GĐ0.5 UI)
    ├── decisions/         DEC-OHANA-NN (01 = web framework + brand kit)
    ├── reviews/           Review artifact JSON (diff-bound, adp-review.sh stamp)
    ├── briefs/            Project-specific briefs
    └── memory/            SESSION_LOG, DECISIONS, KNOWN_ISSUES, REVIEW_QUEUE
```

---

## 7. Anti-patterns (giữ từ DrNick + Ohana-specific)

🚫 Auto-send tới khách KHÔNG qua `policy_gate.py` — kể cả demo/dev.
🚫 Intent nhạy cảm (complaint / refund / price_negotiation / specific_order) auto-send.
🚫 Vector query hoặc DB query KHÔNG include `shop_id` scope SQL-level (post-filter = R1.22 violation).
🚫 Đọc `user_id` / `shop_id` / `role` từ request body hoặc webhook payload thay vì verified JWT.
🚫 Fork nguyên `drnickv4/` repo — luôn port chọn lọc.
🚫 Copy `db/models.py` từ DrNick — single-tenant, phải viết lại tenant-first.
🚫 Skip TDD gate (test ĐỎ trước khi impl) cho phase RISK: high (Phase 2, Phase 5).
🚫 Self-certify DONE mà không qua `adp-checkpoint.sh` (spine quyết, không phải LLM).

🚫 **Dev/placeholder fallback (secret, embedder, sender, mock) KHÔNG gate trên `OHANA_ENV == "dev"`.** Fallback phải fail-LOUD ngoài dev. Docstring `"NOT production-safe"` KHÔNG làm nó an toàn — nó chỉ chứng minh tác giả biết mà vẫn để đó. Đã dính 2 lần trong spec 04:
  - `auth/identity.py get_jwt_secret()` (P0) — fallback literal công khai trong git nuôi CẢ path verify → deploy quên set secret thì mint route 404 đúng nhưng attacker vẫn forge cookie với `shop_id` bất kỳ = **cross-tenant bypass** (R1.22). Mint fail-closed + verify fail-open KHÔNG phải cặp an toàn.
  - `api/admin.py _DeterministicDevEmbedder` (P2) — hash vector giả sẽ khiến ingest trả `{"success": true, "chunks": N}` trong khi ghi vector vô nghĩa → `search_wiki` trả chunk gần-ngẫu-nhiên → **AI trả lời khách sai, không stack trace**. Silent-wrong tệ hơn crash.
  Quy tắc: nếu một fallback chỉ đúng ở dev, gate nó trên cùng tín hiệu dev — và test cái gate đó (xem `test_jwt_secret_refuses_public_fallback`, `test_dev_embedder_refuses_to_run_outside_dev`).

🚫 **Brief cho executor tự liệt kê lại scope thay vì TRÍCH spec.** Brief P0 (spec 04) bảo mount `api/inbox.py` trong khi spec §7 giao việc đó cho P1 → tới P1 thì endpoint đã live, test không RED được, TDD discipline vỡ (ISSUE-012). Brief phải quote spec block, không paraphrase — paraphrase là chỗ scope trôi.

---

## 8. Pre-flight status (updated 2026-07-17)

| ID | Status | Chờ ai | Nội dung / resolution |
|---|---|---|---|
| PRE-001 | ✅ RESOLVED | — | `drnickv4/db/models.py` đọc trong phase 2 discovery; single-tenant confirmed → viết lại tenant-first (`shop_id NOT NULL` mọi bảng). |
| PRE-002 | ⏳ BLOCKING (backfill) | Tân/nền tảng | Ohana platform REST API spec. Phase 4 gate GREEN qua MockTransport contract; `bridge/ohana_client.py` shape locked; F2 tools thứ 2/3/4 (shipping_info/product_info/account_lookup) chờ endpoint list. |
| PRE-003 | ⏳ BLOCKING (backfill) | Tân | Real wiki docs corpus location + format. Phase 3 gate GREEN qua inline fixture; `parsing/{chunk,ingest}.py` + `api/admin.py` ingest endpoint ready to accept real content. |
| PRE-004 | ⏳ BLOCKING (backfill) | Tân | Zalo OA creds + webhook signature + rate-limit. Phase 5 gate GREEN qua `MockZaloSender`; `bridge/zalo_sender.py` interface locked; webhook `enabled=False` default until sig-verify + shops table land. |
| PRE-005 | ✅ RESOLVED | — | Zalo-first confirmed via spec 01 approval 2026-07-16. |
| PRE-006 | ✅ RESOLVED | — | `shop_id` alone sufficient — all Phase 2 tenant-isolation tests pass with single-scalar scope; no `seller_id`/`tenant_id` needed at GĐ0 (revisit if per-seller-many-shops case emerges in Phase 6+). |

Contract gates all GREEN với mock/fixture. Real-content backfill = separate follow-up specs khi source landed, KHÔNG chặn milestone gate.

---

*Router level 1. Workspace router ở `../CLAUDE.md`. Convention thư mục ở `../FOLDER-CONVENTION.md`.*
