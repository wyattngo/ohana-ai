# CLAUDE.md — Ohana AI Seller (project router)

> **Sub-project của workspace `localhost/`.** Router level 0 tại `../CLAUDE.md`.
> Owner: Tân (dev lead) · Approver: Wyatt Ngo (fractional CTO)
> Last updated: 2026-07-19 · Status: **Spec 01 + 02 + 04 + 05 + 06 + 07 = 100% DONE** (ADP 21/31). **General Chat chạy THẬT end-to-end** — seller đăng nhập → màn Chat → Together (Llama-3.3-70B) trả lời, có auth + CSRF + observability. ADR PRE-007 **ACCEPTED**. ⏳ Spec 03 = 0/10 (4 BLOCKED, chờ Tân). ISSUE-010/016/017 vẫn OPEN.

---

## 1. Định danh

| Field | Value |
|---|---|
| Project | Ohana AI Seller (GĐ0 MVP) |
| Kind | AI copilot cho seller social-commerce VN (Zalo/FB/IG) |
| Stack (backend) | Python 3.11 / FastAPI / PostgreSQL + pgvector / Alembic — **fork chọn lọc từ `drnickv4/`**. Redis chưa wire (Phase 3+). |
| Stack (web/) | Vite 8 + React 19 + TypeScript + pnpm + lucide-react (spec 04 / DEC-OHANA-01 §U1). **Node ≥ 20 bắt buộc** — system default trên máy Wyatt là v16, dùng `nvm use v23.6.1` trước mọi lệnh pnpm. Build: `cd web && pnpm install && pnpm build` → `web/dist/` (committed, chưa có CI Node step). |
| Repo | `ohana-ai` — branch `main`, **remote `git@github.com:wyattngo/ohana-ai.git`, đã push** (`main` == `origin/main`) |
| Duration | 3–4 tuần, Zalo-only |
| Priority order | safety → user trust → stability → growth (KHÔNG dùng fintech Survival Framework) |
| Parent workspace | `/Users/wyattngo/Sites/localhost/` |

---

## 2. Trạng thái hiện tại

- ✅ **Spec 01 (5/5)** · ✅ **02 (4/4)** · ✅ **04 (3/3)** · ✅ **05 (3/3)** · ✅ **06 Foundation (3/3)** · ✅ **07 General Chat (3/3)** · ⏳ Spec 03 = 0/10 (4 BLOCKED) · ⏳ Spec 08 = 0/3.
- **Hai bộ đếm, hai câu hỏi khác nhau — đừng lẫn:**
  - `bash .claude/tools/adp-status.sh` → *phase đã ký đi tới đâu?* **21/34 (61%)**
  - `bash .claude/tools/adp-roadmap.sh "$PWD"` → *kế hoạch đã phủ tới đâu?* **internal 8/25 (32%)** + external 0/10 (chờ bên thứ ba, KHÔNG tính vào mục tiêu 100%)
  - Số roadmap thấp hơn vì mẫu số ĐÚNG hơn (25 work item thật, thay vì 34 phase của những spec tình cờ đã viết) — không phải vì tiến độ xấu đi. Xem DEC-OHANA-03.
- Spec canonical: `docs/tasks/01-Task-OhanaAISeller-GD0.md` (GĐ0 backend) + `docs/tasks/04-Task-OhanaAISeller-GD0_5-InboxUI.md` (GĐ0.5 UI). Mọi phase block DONE đều có EVIDENCE stamped.
- Latest STATE_HASH: `d61ee0d167e0` @ spec 07 phase-G2 close (2026-07-19).
- `main` — **đã push, `main` == `origin/main`** (`github.com:wyattngo/ohana-ai`). Spec 06 + 07 commit THẲNG trên `main`. ⚠️ Spec 06 §0 header khai `Branch: adp/06-foundation` — **không đúng thực tế**, branch đó chưa từng được tạo (spec 07 §0 khai `main`, đúng).
- Test suite: **109 test, 0 xfail, 3 deselected (`-m live`)**, ruff sạch, **mypy 0 lỗi / 37 file**. `xfail` cũ (OpenAIClient không import được) đã **ĐẢO CHIỀU** ở spec 07 G0 thành assertion thật — ISSUE-010 vẫn OPEN cho phần alerting, nhưng coupling đã gỡ.
- **Live gate** `tests/test_together_live.py` (`@pytest.mark.live`) — bị `addopts = "-q -m 'not live'"` loại khỏi CI, chạy tay: `pytest tests/test_together_live.py -m live`. Đây là lớp DUY NHẤT bắt được lỗi model-id/endpoint mà fake client không thấy.
- `tests/conftest.py` cung cấp fixture `fresh_db` (drop+create schema, dispose kể cả khi test raise) — test DB mới dùng nó, KHÔNG tự dựng engine.
- **Shipped surface — General Chat (spec 07, 2026-07-19) — lát cắt ship được NGAY, không chờ Tân:**
  - G0 (medium) — `agent/providers/together_client.py` = subclass 17 dòng của `OpenAIClient` (Together OpenAI-compatible ⇒ KHÔNG nhân bản 380 dòng streaming/tool-call). `app/config.py` += `together_api_key` / `together_model` + `DEFAULT_TOGETHER_MODEL`. Gỡ coupling module-level `alert_service` → hook tiêm `on_rate_limit`; **429 re-raise NGUYÊN ở cả 3 nhánh** (không hook / hook chạy êm / hook tự nổ).
  - G1 (medium) — `api/chat.py` `POST /api/chat`, mount TRƯỚC `StaticFiles`. `shop_id` CHỈ từ JWT (`ChatIn` dùng `extra="ignore"` ⇒ body khai shop_id bị bỏ). Thiếu cookie → 401, thiếu CSRF → 403. Content rỗng → **502**, không phải 200 với `reply: ""`. **Gate ranh giới import-graph**: `api/chat.py` chạm sender/`PendingReply`/`agent.policy_gate` là ĐỎ.
  - G2 (low, Wyatt tick) — `web/src/screens/Chat.{tsx,css}` + `postChat()` + `App.tsx` (state-based routing, KHÔNG react-router). Disclaimer "chưa kết nối dữ liệu shop" hiện **thường trực**, không phải tooltip.
  - **`_blank_env_means_unset`** (`app/config.py`) — env khai báo nhưng RỖNG ⇒ coi như chưa set. Áp cho MỌI field. Sinh ra từ bug thật: `TOGETHER_MODEL=` rỗng ghi đè default → falsy → trượt `or` → `TogetherClient` xin `gpt-4o-mini` từ Together → 404.
  - ⚠️ **`.env` KHÔNG được app đọc** — `Settings` cố ý bỏ `env_file` (env_file sẽ đọc file dev cả sau `monkeypatch.delenv`). Dev nạp qua `.claude/launch.json`; production PHẢI set env tường minh.
  - Model = `meta-llama/Llama-3.3-70B-Instruct-Turbo`. **KHÔNG đổi sang MiniMax-M3** dù bảng giá rẻ hơn 3.5× — nó bịa 6/6 lần ở ca an toàn và **đắt hơn 2.4× khi dùng thật** (nói dài gấp 4.5×). Số đo: [DEC-OHANA-02](docs/decisions/DEC-OHANA-02-chat-model-selection.md).
  - **Đo thật:** cold start **24.8s**, call sau ~1.2s ⇒ UI bắt buộc có loading state. `token_cached=0` trên 3 request giống hệt (1236 prompt token) ⇒ **không có bằng chứng cache phía Together**; xem lại sau khi Wiki-RAG land.

- **Shipped surface — Foundation (spec 06, 2026-07-18) — vá nền móng Spec 03 đang đứng trên:**
  - F0 (high) — `db/models.py` thêm `Customer` / `Conversation` / `OrderDraft` tenant-first + Alembic `0003`. **Composite FK `(shop_id, <child_id>)`** → Postgres TỪ CHỐI row shop A trỏ row shop B (FK đơn không chặn được điều đó). FK hoá 2 cột mồ côi `PendingReply.conversation_id/customer_id`. `ConversationRepo` theo pattern `_shop_scope`. Identity type = **TEXT** (PRE-F01 Wyatt ký — KHÔNG migrate sang UUID).
  - F1 (medium) — `channels/{base,identity}.py` + `channels/zalo/`; `api/webhook.py` viết lại generic `/webhook/{channel}/{external_id}` (**VẪN chưa mount**). **Gỡ shim `conversation_id or customer_id`** ở `agent/orchestrator.py` → `conversation_id` là tham số BẮT BUỘC; identity mapping `(channel, external_user_id) → (customer_id, conversation_id)` nằm ở channel layer.
  - F2 (medium, nâng từ low theo floor rule) — `tests/conftest.py` (ĐÓNG ISSUE-014) + **mypy 12→0** (`identity_dep`/`admin_dep` từ `object` → `Callable[..., Identity]`, `_session() -> AsyncIterator`, cast `CursorResult`). ci.yml mypy scope += `db bridge tools`.
  - ⚠️ **NỢ: `channels/identity.py` thiếu unique `(shop_id, customer_id, channel)`** → race có thể tạo 2 Conversation. Vô hại vì webhook chưa mount; **PHẢI thêm constraint trước khi Spec 03c mount webhook** (ISSUE-017).
- **Shipped surface — Config + Embedder thật (spec 05, 2026-07-18):**
  - P0 (medium) — `app/config.py` `Settings(BaseSettings)` + `get_settings()` lru_cache (4 field: `openai_api_key`, `openai_embed_model="text-embedding-3-small"` 1536-dim, `openai_model`, `reasoning_models`). `OpenAIEmbedder` hết `ModuleNotFoundError`. gate `test_config.py`.
  - P1 (medium) — `api/admin.py default_embedder()` env-selecting: key→`OpenAIEmbedder` thật; no-key→`_DeterministicDevEmbedder` (raise-outside-dev ở `embed()`, KHÔNG ở factory — vì `app/main.py` gọi lúc import). gate `test_embedder_wiring.py` (offline, inject fake client) + `test_wiki_rag_live.py` (`@pytest.mark.live`, DoD #5).
  - P2 (medium) — `get_jwt_secret()` + `db/session.py get_database_url()` đọc qua `Settings()` **fresh mỗi call** (KHÔNG `get_settings()` cached — né cache-staleness trên security path). Fail-closed byte-identical.
  - ⚠️ **ISSUE-016 vẫn OPEN — và đã ĐỔI BẢN CHẤT**: ADR `docs/adr/2026-07-18-hosting-region.md` chốt provider = **Together AI open-weight**, embedding chuyển `text-embedding-3-small` (1536) → `intfloat/multilingual-e5-large-instruct` (**1024-dim**). Nghĩa là live acceptance phải chạy trên **e5, KHÔNG phải OpenAI**, và cần migration đổi dim `Vector(1536)` + re-embed corpus. ADR **ACCEPTED 2026-07-19** (Wyatt): deployment-region = Together US serverless ngay, self-host VN/SG khi residency buộc. ⚠️ Legal path (Open-Q #4) **CỐ Ý để mở** — chữ ký chốt kiến trúc, KHÔNG đóng nghĩa vụ PDPL; TIA/consent chưa có chủ, đồng hồ 60 ngày chạy từ tin nhắn khách THẬT đầu tiên (Spec 03c mount webhook).
- **Shipped surface — GĐ0.5 UI (spec 04, 2026-07-17):**
  - P0 (medium) — `web/` Vite+React+TS scaffold, `web/src/lib/tokens.ts` (Astronixa tokens frozen), `auth/identity.py identity_from_cookie()` + `get_jwt_secret()` fail-closed, CSRF double-submit middleware trong `app/main.py`, `api/mock_auth.py` `POST /api/mock/authorize` (dev-only, `?role=admin`), gate `test_web_scaffold.py` 6/6.
  - P1 (medium) — 3 màn seller `web/src/screens/{ChannelPicker,Inbox,ReviewCard}.tsx` + `web/src/lib/api.ts` (CSRF tập trung trong `apiFetch`), state-based routing (KHÔNG react-router), gate `test_inbox_ui_e2e.py` 4/4. **Wyatt smoke browser xác nhận chạy thật.**
  - P2 (medium — nâng từ low theo floor rule vì chạm `auth/`) — `auth/identity.py require_admin()`, `api/admin.py` guard + mount (trước đó route này KHÔNG xác thực), `web/src/screens/AdminWikiIngest.tsx`, gate `test_admin_ui.py` 4/4.
  - Routes mounted trong `app/main.py`: `/api/inbox` (3), `/api/mock/authorize` (dev-only), `/api/admin/wiki/ingest` (require_admin), **`/api/chat` (spec 07 G1)**, `StaticFiles(web/dist)` ở `/` **mount CUỐI** (catch-all — mount trước sẽ che `/api/*`). `api/webhook.py` **vẫn chưa mount** (thiếu concrete `Drafter` impl).
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
RISK_PATHS: agent/orchestrator.py, agent/policy_gate.py, tools/registry.py, bridge/, auth/, db/migrations, api/webhook.py, api/inbox.py, api/admin.py, api/chat.py
SPEC_DIR: docs/tasks
ROADMAP_L1: docs/ROADMAP.md
ROADMAP_L3: docs/ROADMAP-STATUS.md
EXECUTOR_SKILL: drnick-coder
CHECKPOINT_PREFIX: adp

### Khoá nối Roadmap (bắt buộc từ 2026-07-19 — DEC-OHANA-03)

Mỗi ADP phase block **PHẢI** có dòng `ROADMAP:` trỏ về một ID trong `docs/ROADMAP.md §4`:

```
ROADMAP: GD0-EVAL     # đặt ngay sau STATUS:
```

**Ba tầng, ba chủ sở hữu — đừng trộn:**

| Tầng | File | Ai viết | Sửa khi nào |
|---|---|---|---|
| L1 | `docs/ROADMAP.md` | **người** | đổi ý định/kế hoạch |
| L2 | `docs/tasks/*.md` | senior-engineer → frozen | mở spec mới |
| L3 | `docs/ROADMAP-STATUS.md` | **máy** — `bash .claude/tools/adp-roadmap.sh "$PWD"` | không bao giờ sửa tay |

`adp-checkpoint.sh` tự sinh lại L3 sau khi stamp EVIDENCE. **Checkpoint KHÔNG ghi vào L1** — L1 là tầng ý định, chỉ người viết.

⚠️ **L1 nằm NGOÀI spec-lock có chủ ý.** `adp_spec_lock_verify` chỉ khoá `SPEC_DIR`. Kéo L1 vào vùng diff-bound = mỗi lần re-plan giữa sprint bị checkpoint REFUSE vì DRIFT, tức máy cấm đổi ý. Đừng "sửa" điều này.

**Mục tiêu 100% = mẫu số `internal`** (không gộp `external` chờ bên thứ ba, không gộp GĐ4). L3 phát hiện drift hai chiều: `uncovered` (mục roadmap chưa spec nào nhận) + `unplanned` (phase làm việc ngoài kế hoạch).

### SMOKE gate (bắt buộc từ 2026-07-19 — Wyatt directive sau spec 07)

Mỗi ADP phase block **PHẢI** có dòng `SMOKE:`. `adp-checkpoint.sh` REFUSE nếu thiếu.

```
SMOKE: PASS ref=docs/smokes/<spec>-<phase>.md    # có mặt runtime
SMOKE: N/A <lý do cụ thể, ≥12 ký tự>             # không có mặt runtime
```

**Vì sao có gate này.** Spec 07 ship **3 lỗi** mà 107 test xanh + mypy 0 + 3 vòng review đều KHÔNG thấy:

| Lỗi | Vì sao test không thấy |
|---|---|
| `TogetherClient` gọi Together bằng `gpt-4o-mini` → 404 | mọi test tiêm fake client; fake không quan tâm model id có thật không |
| Model đã ký không tồn tại dạng serverless → 400 | có trong `/v1/models` **kèm bảng giá** mà gọi vẫn hỏng — danh sách không phải bằng chứng |
| `logger.info` bị uvicorn nuốt (root không handler, mức WARNING) | `caplog.at_level(INFO)` **tự ép mức**; nó chứng minh "code có gọi logger", không chứng minh "log tới production" |

Cộng thêm 2 lỗi layout G2 (ô nhập bị bóp còn một sợi; ô nhập bị đẩy khỏi màn hình khi hội thoại dài) — repo không có Playwright nên **không test nào có khả năng thấy**.

Mẫu chung: **test đo môi trường TEST; smoke đo môi trường THẬT.** Không cái nào thay được cái nào.

**Thứ tự thao tác (đừng đảo bước 3–4):**
```bash
bash .claude/tools/adp-smoke.sh new "$PWD" docs/smokes/<spec>-<phase>.md <phase>
# → chạy tay, điền OBSERVED bằng output THẬT (dán vào, không viết "OK")
# → ghi 'SMOKE: PASS ref=…' vào ADP block        ← TRƯỚC stamp
bash .claude/tools/adp-smoke.sh stamp "$PWD" docs/smokes/<spec>-<phase>.md
bash .claude/tools/adp-checkpoint.sh
```
Ghi dòng SMOKE **là** một thay đổi trong `git diff HEAD` — stamp trước rồi ghi sau ⇒ hash lệch ⇒ REFUSE. (Đã dính đúng bẫy này với `REVIEW:` ở spec 06 F1.)

**Chống con dấu cao su:** `stamp` từ chối nếu artifact còn placeholder `(dán…)`, thiếu `SMOKED_BY`, hoặc `VERDICT` chưa `PASS`. Checkpoint kiểm lại y hệt + đòi `diff_sha256` khớp `git diff HEAD` — smoke cũ **không** áp dụng cho code đã đổi.

**`N/A` là lối thoát hợp lệ, không phải lối tắt.** Phase không có mặt runtime (vd spec 06 F2: typing + conftest) thì ghi N/A kèm lý do. Bắt smoke cho những phase đó chỉ đẻ ra tick bừa — mà tick bừa tệ hơn không có ô tick, vì nó *trông như* đã kiểm.
<!-- /ADP -->

**Isolation**: Ohana AI dùng ADP v2.3 riêng (`ohana-ai/.claude/`), KHÔNG dùng workspace v1.3 của Onfa/DrNick. Sandbox: an toàn để calibrate decision-gate (SHADOW → hard-block sau ≥5 real decisions).

Xem `docs/adr/hook-contract.md` + `MODEL.md` bundle export cho contract chi tiết. Workspace router `../CLAUDE.md §4.7` mô tả v1.3 flow (áp dụng Onfa/DrNick).

---

## 6. Layout thực tế (verified 2026-07-19 sau spec 07)

```
ohana-ai/
├── CLAUDE.md              ← File này (router project)
├── pyproject.toml
├── Dockerfile
├── .env.example           Template env cho admin (secret để RỖNG — placeholder là truthy!)
├── app/                   FastAPI entrypoint
├── agent/                 orchestrator, llm_client, embedder, policy_gate (NET-NEW)
│   └── providers/         LLM providers — openai_client.py · together_client.py (spec 07 G0)
│                           (KHÔNG phải top-level `providers/` — sửa drift 2026-07-18)
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
│   ├── inbox.py           Seller inbox (list/approve/reject) — duyệt reply GỬI KHÁCH.
│                           KHÁC chat.py: chat = seller↔AI nội bộ, không tới khách.
│   ├── mock_auth.py       Dev-only authorize (guard OHANA_ENV=="dev")
│   ├── chat.py            General Chat POST /api/chat (spec 07 G1 — ĐÃ mount)
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
│   │   └── screens/         ChannelPicker · Inbox · ReviewCard · AdminWikiIngest · Chat
│   └── dist/              Build output — COMMITTED (chưa có CI Node step)
├── tests/
├── .claude/               (port từ drnickv4/ khi bootstrap)
└── docs/
    ├── ROADMAP.md         ★ L1 — ý định + lý do + ID bền. NGƯỜI viết. KHÔNG có STATUS.
    ├── ROADMAP-STATUS.md  ★ L3 — SINH MÁY (adp-roadmap.sh). Đừng sửa tay trên NOTES_HUMAN.
    ├── tasks/             Spec ADP = L2 (01 GĐ0 · 02 bootstrap · 03 backfill · 04 GĐ0.5 UI
    │                       · 05 config/embedder · 06 foundation · 07 general chat
    │                       · 08 embedder-swap). Mỗi phase block PHẢI có `ROADMAP:`.
    ├── archive/           Tài liệu đã retire (roadmap v3 hoá thạch + 2 PLAN companion)
    ├── decisions/         DEC-OHANA-NN (01 web framework · 02 chat model · 03 roadmap-ADP spine)
    ├── reviews/           Review artifact JSON (diff-bound, adp-review.sh stamp)
    ├── smokes/            SMOKE artifact chạy tay (diff-bound, adp-smoke.sh stamp) — §5
    ├── adr/               ADR (2026-07-18-hosting-region.md = PRE-007, ACCEPTED)
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
