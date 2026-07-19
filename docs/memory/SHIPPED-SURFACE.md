# SHIPPED SURFACE — ledger chi tiết theo spec

> Tách khỏi `CLAUDE.md` ngày 2026-07-19 khi chuẩn hoá format router.
> **Nội dung chuyển nguyên văn, không sửa fact.** CLAUDE.md giữ lại quy tắc rút ra;
> file này giữ lại *cái đã ship và vì sao*.
>
> Đọc file này khi: cần biết một module ra đời ở phase nào, vì sao nó có hình dạng
> hiện tại, hoặc trước khi sửa code chạm vào một quyết định đã ký.
> KHÔNG cần đọc mỗi session — `CLAUDE.md` đủ cho việc thường ngày.

---

## Spec 07 — General Chat (2026-07-19)

Lát cắt ship được NGAY, không chờ Tân.

- **G0 (medium)** — `agent/providers/together_client.py` = subclass 17 dòng của `OpenAIClient` (Together OpenAI-compatible ⇒ KHÔNG nhân bản 380 dòng streaming/tool-call). `app/config.py` += `together_api_key` / `together_model` + `DEFAULT_TOGETHER_MODEL`. Gỡ coupling module-level `alert_service` → hook tiêm `on_rate_limit`; **429 re-raise NGUYÊN ở cả 3 nhánh** (không hook / hook chạy êm / hook tự nổ).
- **G1 (medium)** — `api/chat.py` `POST /api/chat`, mount TRƯỚC `StaticFiles`. `shop_id` CHỈ từ JWT (`ChatIn` dùng `extra="ignore"` ⇒ body khai shop_id bị bỏ). Thiếu cookie → 401, thiếu CSRF → 403. Content rỗng → **502**, không phải 200 với `reply: ""`. **Gate ranh giới import-graph**: `api/chat.py` chạm sender/`PendingReply`/`agent.policy_gate` là ĐỎ.
- **G2 (low, Wyatt tick)** — `web/src/screens/Chat.{tsx,css}` + `postChat()` + `App.tsx` (state-based routing, KHÔNG react-router). Disclaimer "chưa kết nối dữ liệu shop" hiện **thường trực**, không phải tooltip.
- **`_blank_env_means_unset`** (`app/config.py`) — env khai báo nhưng RỖNG ⇒ coi như chưa set. Áp cho MỌI field. Sinh ra từ bug thật: `TOGETHER_MODEL=` rỗng ghi đè default → falsy → trượt `or` → `TogetherClient` xin `gpt-4o-mini` từ Together → 404.
- ⚠️ **`.env` KHÔNG được app đọc** — `Settings` cố ý bỏ `env_file` (env_file sẽ đọc file dev cả sau `monkeypatch.delenv`). Dev nạp qua `.claude/launch.json`; production PHẢI set env tường minh.
- Model = `meta-llama/Llama-3.3-70B-Instruct-Turbo`. **KHÔNG đổi sang MiniMax-M3** dù bảng giá rẻ hơn 3.5× — nó bịa 6/6 lần ở ca an toàn và **đắt hơn 2.4× khi dùng thật** (nói dài gấp 4.5×). Số đo: [DEC-OHANA-02](../decisions/DEC-OHANA-02-chat-model-selection.md).
- **Đo thật:** cold start **24.8s**, call sau ~1.2s ⇒ UI bắt buộc có loading state. `token_cached=0` trên 3 request giống hệt (1236 prompt token) ⇒ **không có bằng chứng cache phía Together**; xem lại sau khi Wiki-RAG land.

### Vì sao spec 07 đẻ ra SMOKE gate

Spec 07 ship **3 lỗi** mà 107 test xanh + mypy 0 + 3 vòng review đều KHÔNG thấy:

| Lỗi | Vì sao test không thấy |
|---|---|
| `TogetherClient` gọi Together bằng `gpt-4o-mini` → 404 | mọi test tiêm fake client; fake không quan tâm model id có thật không |
| Model đã ký không tồn tại dạng serverless → 400 | có trong `/v1/models` **kèm bảng giá** mà gọi vẫn hỏng — danh sách không phải bằng chứng |
| `logger.info` bị uvicorn nuốt (root không handler, mức WARNING) | `caplog.at_level(INFO)` **tự ép mức**; nó chứng minh "code có gọi logger", không chứng minh "log tới production" |

Cộng thêm 2 lỗi layout G2 (ô nhập bị bóp còn một sợi; ô nhập bị đẩy khỏi màn hình khi hội thoại dài) — repo không có Playwright nên **không test nào có khả năng thấy**.

Mẫu chung: **test đo môi trường TEST; smoke đo môi trường THẬT.** Không cái nào thay được cái nào.

---

## Spec 06 — Foundation (2026-07-18)

Vá nền móng Spec 03 đang đứng trên.

- **F0 (high)** — `db/models.py` thêm `Customer` / `Conversation` / `OrderDraft` tenant-first + Alembic `0003`. **Composite FK `(shop_id, <child_id>)`** → Postgres TỪ CHỐI row shop A trỏ row shop B (FK đơn không chặn được điều đó). FK hoá 2 cột mồ côi `PendingReply.conversation_id/customer_id`. `ConversationRepo` theo pattern `_shop_scope`. Identity type = **TEXT** (PRE-F01 Wyatt ký — KHÔNG migrate sang UUID).
- **F1 (medium)** — `channels/{base,identity}.py` + `channels/zalo/`; `api/webhook.py` viết lại generic `/webhook/{channel}/{external_id}` (**VẪN chưa mount**). **Gỡ shim `conversation_id or customer_id`** ở `agent/orchestrator.py` → `conversation_id` là tham số BẮT BUỘC; identity mapping `(channel, external_user_id) → (customer_id, conversation_id)` nằm ở channel layer.
- **F2 (medium, nâng từ low theo floor rule)** — `tests/conftest.py` (ĐÓNG ISSUE-014) + **mypy 12→0** (`identity_dep`/`admin_dep` từ `object` → `Callable[..., Identity]`, `_session() -> AsyncIterator`, cast `CursorResult`). ci.yml mypy scope += `db bridge tools`.
- ⚠️ **NỢ: `channels/identity.py` thiếu unique `(shop_id, customer_id, channel)`** → race có thể tạo 2 Conversation. Vô hại vì webhook chưa mount; **PHẢI thêm constraint trước khi Spec 03c mount webhook** (ISSUE-017).
- ⚠️ Spec 06 §0 header khai `Branch: adp/06-foundation` — **không đúng thực tế**, branch đó chưa từng được tạo. Spec 06 + 07 commit THẲNG trên `main` (spec 07 §0 khai `main`, đúng).

---

## Spec 05 — Config + Embedder thật (2026-07-18)

- **P0 (medium)** — `app/config.py` `Settings(BaseSettings)` + `get_settings()` lru_cache (4 field: `openai_api_key`, `openai_embed_model="text-embedding-3-small"` 1536-dim, `openai_model`, `reasoning_models`). `OpenAIEmbedder` hết `ModuleNotFoundError`. gate `test_config.py`.
- **P1 (medium)** — `api/admin.py default_embedder()` env-selecting: key→`OpenAIEmbedder` thật; no-key→`_DeterministicDevEmbedder` (raise-outside-dev ở `embed()`, KHÔNG ở factory — vì `app/main.py` gọi lúc import). gate `test_embedder_wiring.py` (offline, inject fake client) + `test_wiki_rag_live.py` (`@pytest.mark.live`, DoD #5).
- **P2 (medium)** — `get_jwt_secret()` + `db/session.py get_database_url()` đọc qua `Settings()` **fresh mỗi call** (KHÔNG `get_settings()` cached — né cache-staleness trên security path). Fail-closed byte-identical.
- ⚠️ **ISSUE-016 vẫn OPEN — và đã ĐỔI BẢN CHẤT**: ADR `docs/adr/2026-07-18-hosting-region.md` chốt provider = **Together AI open-weight**, embedding chuyển `text-embedding-3-small` (1536) → `intfloat/multilingual-e5-large-instruct` (**1024-dim**). Nghĩa là live acceptance phải chạy trên **e5, KHÔNG phải OpenAI**, và cần migration đổi dim `Vector(1536)` + re-embed corpus. ADR **ACCEPTED 2026-07-19** (Wyatt): deployment-region = Together US serverless ngay, self-host VN/SG khi residency buộc. ⚠️ Legal path (Open-Q #4) **CỐ Ý để mở** — chữ ký chốt kiến trúc, KHÔNG đóng nghĩa vụ PDPL; TIA/consent chưa có chủ, đồng hồ 60 ngày chạy từ tin nhắn khách THẬT đầu tiên (Spec 03c mount webhook).

---

## Spec 04 — GĐ0.5 UI (2026-07-17)

- **P0 (medium)** — `web/` Vite+React+TS scaffold, `web/src/lib/tokens.ts` (Astronixa tokens frozen), `auth/identity.py identity_from_cookie()` + `get_jwt_secret()` fail-closed, CSRF double-submit middleware trong `app/main.py`, `api/mock_auth.py` `POST /api/mock/authorize` (dev-only, `?role=admin`), gate `test_web_scaffold.py` 6/6.
- **P1 (medium)** — 3 màn seller `web/src/screens/{ChannelPicker,Inbox,ReviewCard}.tsx` + `web/src/lib/api.ts` (CSRF tập trung trong `apiFetch`), state-based routing (KHÔNG react-router), gate `test_inbox_ui_e2e.py` 4/4. **Wyatt smoke browser xác nhận chạy thật.**
- **P2 (medium — nâng từ low theo floor rule vì chạm `auth/`)** — `auth/identity.py require_admin()`, `api/admin.py` guard + mount (trước đó route này KHÔNG xác thực), `web/src/screens/AdminWikiIngest.tsx`, gate `test_admin_ui.py` 4/4.
- Design system: Astronixa "OHANA" Figma `JRoD28RIxiEfSEgVqDZLNJ` — 6 palette × 10 shade, Inter, CTA gradient 3-stop. **KHÔNG có semantic palette** (danger/warning/success) → intent badge dùng icon + label VI, xem DEC-OHANA-01 §U2.

### Hai lần dính dev-fallback không gate (nguồn của anti-pattern §5 CLAUDE.md)

- `auth/identity.py get_jwt_secret()` (P0) — fallback literal công khai trong git nuôi CẢ path verify → deploy quên set secret thì mint route 404 đúng nhưng attacker vẫn forge cookie với `shop_id` bất kỳ = **cross-tenant bypass** (R1.22). Mint fail-closed + verify fail-open KHÔNG phải cặp an toàn.
- `api/admin.py _DeterministicDevEmbedder` (P2) — hash vector giả sẽ khiến ingest trả `{"success": true, "chunks": N}` trong khi ghi vector vô nghĩa → `search_wiki` trả chunk gần-ngẫu-nhiên → **AI trả lời khách sai, không stack trace**. Silent-wrong tệ hơn crash.

Quy tắc rút ra: nếu một fallback chỉ đúng ở dev, gate nó trên cùng tín hiệu dev — và **test cái gate đó** (`test_jwt_secret_refuses_public_fallback`, `test_dev_embedder_refuses_to_run_outside_dev`).

### Brief paraphrase làm vỡ TDD (nguồn của anti-pattern §5 CLAUDE.md)

Brief P0 bảo mount `api/inbox.py` trong khi spec §7 giao việc đó cho P1 → tới P1 thì endpoint đã live, test không RED được, TDD discipline vỡ (ISSUE-012). Brief phải **quote** spec block, không paraphrase — paraphrase là chỗ scope trôi.

---

## Spec 01 — GĐ0 backend (2026-07-16 → 17)

- **Phase 2 (RISK:high)** — `auth/identity.py` HS256, `db/{models,session,repos}.py` tenant-first + Alembic 0001, `retrieval/pgvector.py PgvectorRetriever(shop_scope=)` SQL-level hard filter, gate `tests/test_tenant_isolation.py` 3/3.
- **Phase 3 (low)** — `parsing/{chunk,ingest}.py`, `tools/{registry,wiki}.py`, `api/admin.py` ingest, gate `test_wiki_rag.py` 2/2 (happy + adversarial ns iso). Gate deterministic chạy bằng `FakeEmbedder` inline. **Spec 05 đã wire `OpenAIEmbedder` thật** — nhưng ⚠️ **F1 chưa nghiệm thu với embedding thật**: DoD #5 (`tests/test_wiki_rag_live.py -m live`) chờ chạy tay. **ISSUE-016 (high) vẫn OPEN** cho tới lúc đó — code-complete ≠ F1-verified.
- **Phase 4 (medium)** — `bridge/ohana_client.py` R1.1-extended REST client (verify=True hardcoded), `tools/ohana_read.py order_status`, gate `test_ohana_tools.py` 10/10 (MockTransport).
- **Phase 5 (RISK:high)** — `agent/{policy_gate,orchestrator}.py`, `db/models.py PendingReply` + Alembic 0002, `bridge/zalo_sender.py MockZaloSender`, `api/{webhook,inbox}.py` scaffolds, gate `test_policy_gate + test_orchestrator + test_tenant_isolation` 12/12.

---

## Pre-flight — lịch sử đầy đủ

| ID | Status | Chờ ai | Nội dung / resolution |
|---|---|---|---|
| PRE-001 | ✅ RESOLVED | — | `drnickv4/db/models.py` đọc trong phase 2 discovery; single-tenant confirmed → viết lại tenant-first (`shop_id NOT NULL` mọi bảng). |
| PRE-002 | ⏳ BLOCKING (backfill) | Tân/nền tảng | Ohana platform REST API spec. Phase 4 gate GREEN qua MockTransport contract; `bridge/ohana_client.py` shape locked; F2 tools thứ 2/3/4 (shipping_info/product_info/account_lookup) chờ endpoint list. |
| PRE-003 | ⏳ BLOCKING (backfill) | Tân | Real wiki docs corpus location + format. Phase 3 gate GREEN qua inline fixture; `parsing/{chunk,ingest}.py` + `api/admin.py` ingest endpoint ready to accept real content. |
| PRE-004 | ⏳ BLOCKING (backfill) | Tân | Zalo OA creds + webhook signature + rate-limit. Phase 5 gate GREEN qua `MockZaloSender`; `bridge/zalo_sender.py` interface locked; webhook `enabled=False` default until sig-verify + shops table land. |
| PRE-005 | ✅ RESOLVED | — | Zalo-first confirmed via spec 01 approval 2026-07-16. |
| PRE-006 | ✅ RESOLVED | — | `shop_id` alone sufficient — all Phase 2 tenant-isolation tests pass with single-scalar scope; no `seller_id`/`tenant_id` needed at GĐ0 (revisit if per-seller-many-shops case emerges in Phase 6+). |

Contract gates all GREEN với mock/fixture. Real-content backfill = separate follow-up specs khi source landed, KHÔNG chặn milestone gate.
