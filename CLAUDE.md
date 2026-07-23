# CLAUDE.md — Ohana AI Seller

AI copilot cho seller social-commerce VN (Zalo/FB/IG). GĐ0 MVP, Zalo-only.
Backend Python 3.11 / FastAPI / PostgreSQL + pgvector / Alembic · Frontend Vite + React 19 + TS (`web/`).

- **Ưu tiên:** safety → user trust → stability → growth *(KHÔNG dùng fintech Survival Framework)*.
- **Multi-tenant là bất biến cốt lõi:** mọi dữ liệu scope theo `shop_id` ở tầng SQL.
- Owner: Tân (dev) · Approver: Wyatt Ngo (CTO). Fork **chọn lọc** từ `drnickv4/` — KHÔNG fork nguyên repo.

Đây là entrypoint. Lịch sử + trạng thái sống nằm ở `docs/` (§7) — **đừng nhét changelog vào file này**.

---

## 1. Commands

Backend (dùng `.venv/bin/…` nếu có venv; CI dùng `pip install -e ".[dev]"`):

```bash
pytest -q                   # default gate — live test bị loại (addopts: -m 'not live')
pytest -q -x                # GATE_RUNNER của ADP, dừng ở lỗi đầu
ruff check . --no-cache     # lint (E,F,I,B,UP,S — gồm bandit S). --no-cache BẮT BUỘC: xem §4
ruff format --check . --no-cache
mypy app agent retrieval parsing storage db bridge tools api auth   # strict; TOÀN BỘ code sản phẩm, không loại thư mục nào
alembic upgrade head        # cần DATABASE_URL trỏ Postgres+pgvector

# Live smoke — real net, nondeterministic, KHÔNG chạy trong CI. Chạy tay khi đổi model/endpoint:
pytest -m live
pytest tests/test_together_live.py -m live     # bắt lỗi model-id/endpoint mà fake client KHÔNG thấy
pytest tests/test_wiki_rag_live.py -m live     # F1 wiki-RAG trên e5 THẬT — assert THỨ HẠNG chunk
```

Frontend (`web/`) — **Node ≥ 20 bắt buộc**, system default máy Wyatt là v16 ⇒ `nvm use v23.6.1` trước mọi lệnh pnpm:

```bash
cd web && pnpm install && pnpm build   # → web/dist/ (COMMITTED — chưa có CI Node step)
pnpm dev                               # vite dev server
pnpm lint                              # oxlint
```

ADP:

```bash
bash .claude/tools/adp-status.sh          # phase đã ký tới đâu
bash .claude/tools/adp-roadmap.sh "$PWD"  # kế hoạch phủ tới đâu (sinh lại L3)
bash .claude/tools/adp-dashboard.sh       # spine-state + audit-log, chạy TAY khi forensic

# Derivation pipeline (ADR 2026-07-22):
python3 scripts/roadmap_derive.py verify   # GATE: dangling anchor → exit≠0. Có trong CI.
python3 scripts/roadmap_derive.py tree     # Phase → Step → Work item → Task (terminal)
python3 scripts/roadmap_dashboard.py       # → docs/roadmap-dashboard.html — DASHBOARD DUY NHẤT,
                                           # tự refresh ở checkpoint + session-start
bash .claude/tools/adp-checkpoint.sh      # con đường DUY NHẤT để một phase thành DONE
```

CI (`.github/workflows/ci.yml`): guardrail hook → ruff lint → ruff format → mypy → **codebase-map `--check`** → **derivation map `verify`** → alembic upgrade → pytest, trên service **Postgres (pgvector:pg16) + Redis 7 thật**. Frontend chưa có job.
⚠️ Hai step in đậm **KHÔNG có trong vòng verify local mặc định** — chúng là lý do CI đỏ 12 run mà local vẫn xanh (§7). Chạy cả hai trước khi push.

---

## 2. Architecture / Layout

```
app/          FastAPI entrypoint. main.py = NƠI DUY NHẤT wire concrete deps vào router
              factory (build_*_router(...)). config.py = Settings(BaseSettings) + get_settings() lru_cache.
agent/        orchestrator (history load + cap kép) · llm_client · embedder · policy_gate · persona (build_persona_prompt — hàm thuần, cap cứng)
  providers/  openai_client · together_client (subclass 17 dòng) · openai_embedder · together_embedder (e5)
channels/     base (Protocol) · identity (resolve_conversation — upsert, race-safe) · zalo/ adapter
retrieval/    pgvector.py — PgvectorRetriever(shop_scope=) hard filter SQL-level
parsing/      chunk · ingest · extract (Wiki doc)
storage/      base · local
bridge/       ohana_client (REST platform API, verify=True) · zalo_sender (MockZaloSender)
auth/         identity.py — HS256 JWT (user_id, shop_id, role) · require_admin · CSRF
tools/        registry · wiki (search_wiki) · ohana_read (order_status) · shop_kb (lookup_size/lookup_shipping — tất định, KHÔNG RAG)
api/          admin (require_admin) · inbox · mock_auth (dev-only) · chat (mounted) · webhook (CHƯA mount)
db/           models.py (tenant-first) · repos (Conversation/PendingReply/Message/ShopProfile/WebhookEvent) · session · migrations/ (Alembic 0001–0009)
web/          Vite+React+TS. State-based routing (KHÔNG react-router). dist/ committed.
tests/        pytest; conftest.py cung cấp fixture fresh_db (drop+create schema, dispose kể cả khi raise)
.claude/      ADP v2.3 — hooks/ (guardrail.py) + tools/ (adp-*.sh)
scripts/      ai_coder/gen_codebase_map.py (CI gate) · roadmap_derive.py (verify|derive|tree)
              · roadmap_dashboard.py + .tpl.html → docs/roadmap-dashboard.html (gitignored)
docs/         backend-workflow.md (**nguồn WHY, có anchor**) · gates/ (9 gate đã ký = tầng Step)
              · tasks/ (spec = L2) · ROADMAP.md (L1, §4.1.1 derivation map) · ROADMAP-STATUS.md (L3 máy sinh)
              · decisions/ · adr/ · reviews/ · smokes/ · memory/ · briefs/ · archive/
```

**Derivation pipeline 4 tầng** (ADR `docs/adr/2026-07-22-derivation-pipeline.md`, ACCEPTED):

```
backend-workflow.md   WHY + shape — Wyatt viết, mang <!-- anchor:w-… -->
    ↓ derives_from (enforce: scripts/roadmap_derive.py verify — CI step + pre-commit)
docs/gates/           Target + Tests, CC propose → Wyatt ký (approved_by)
    ↓ contracts
ROADMAP.md §4.1.1     work item + derives_from → anchor
    ↓ triage
docs/tasks/           L2 spec — sinh **JIT khi code**, KHÔNG preemptive
```

⚠️ **Anchor gần như immutable.** Rename chỉ được khi **safety-driven** VÀ audit mọi
`derives_from` **cùng commit** với gate xanh (ADR §5.0). Sửa workflow §7 mà quên §4.1.1 ⇒
`verify` đỏ, block commit — nó đã bắt đúng 12 dangling một lần.

**Mount order (`app/main.py`):** mọi `/api/*` router include **TRƯỚC** `StaticFiles(web/dist)` ở `/` — static là catch-all, mount trước sẽ che hết `/api/*`.

**`inbox` vs `chat` — đừng lẫn:** `api/inbox.py` = seller duyệt reply **GỬI KHÁCH** (qua `policy_gate`). `api/chat.py` = seller ↔ AI **nội bộ** (General Chat), KHÔNG tới khách. Ranh giới có gate import-graph: `api/chat.py` chạm sender / `PendingReply` / `agent.policy_gate` là ĐỎ.

### Nguồn port từ `drnickv4/`

| Từ `drnickv4/` | Sang `ohana-ai/` | Ghi chú |
|---|---|---|
| `agent/llm_client.py` + `providers/` | cùng path | reuse nguyên |
| `agent/embedder.py`, `retrieval/`, `parsing/`, `storage/` | cùng path | reuse — thêm `shop_id` scope SQL-level |
| `agent/orchestrator.py` | cùng path | adapt async cho pending_reply |
| `tools/registry.py` | cùng path | port nguyên shape Tool dataclass |
| `bridge/onfa_client.py` | `bridge/ohana_client.py` | viết mới, pattern REST + `verify=True` |
| `auth/identity.py` + `auth/jwt.py` | cùng path | mở rộng JWT claim `(user_id, shop_id, role)` |
| `db/models.py` | **viết lại tenant-first** | KHÔNG copy — DrNick single-tenant |
| `.claude/hooks/guardrail.py` | cùng path | đổi R1.13 money → intent-safety Ohana |

**KHÔNG port:** `tools/onfa_actions.py`, `pending_action` financial logic, ConfirmEvent 2FA path.

---

## 3. Safety rules — KHÔNG vi phạm

Bất biến bảo mật. `.claude/hooks/guardrail.py` chặn cơ học **một phần** (regex trên source) — nó là lưới, không phải chứng minh.

- **Tenant scope:** mọi vector/DB query PHẢI có `shop_id` scope ở **tầng SQL**. Post-filter = vi phạm R1.22. Composite FK `(shop_id, <child_id>)` để Postgres từ chối row cross-tenant — FK đơn KHÔNG chặn được.
- **Identity từ JWT, KHÔNG từ body/webhook:** đọc `user_id` / `shop_id` / `role` từ verified JWT. `ChatIn` dùng `extra="ignore"` ⇒ body khai `shop_id` bị bỏ.
- **KHÔNG auto-send tới khách ngoài `policy_gate.py`** — kể cả demo/dev. Intent nhạy cảm (complaint / refund / price_negotiation / specific_order) KHÔNG bao giờ auto-send.
- **KHÔNG `verify=False`** trên HTTP client (guardrail Rule #3 deny).
- **Dev/placeholder fallback** (secret, embedder, sender, mock) PHẢI gate trên `OHANA_ENV=="dev"` và **fail-LOUD** ngoài dev. Docstring `"NOT production-safe"` KHÔNG làm nó an toàn — nó chỉ chứng minh tác giả biết mà vẫn để đó. Đã dính 2 lần (spec 04):
  - `get_jwt_secret()` — fallback literal công khai nuôi CẢ path verify ⇒ attacker forge cookie với `shop_id` bất kỳ = cross-tenant bypass. Mint fail-closed + verify fail-open KHÔNG phải cặp an toàn.
  - `_DeterministicDevEmbedder` — vector giả ⇒ ingest báo `success: true` nhưng `search_wiki` trả chunk gần-ngẫu-nhiên ⇒ **AI trả lời khách sai, không stack trace**. Silent-wrong tệ hơn crash.
  - Quy tắc: fallback chỉ đúng ở dev thì gate trên cùng tín hiệu dev — **và test cái gate đó**.
- **Idempotency của inbound phải nằm ở tầng DB, không ở code:** `resolve_conversation()` upsert
  `Customer` (`uq_customers_shop_chan_ext`) và `Conversation`
  (`uq_conversations_shop_cus_chan_thread`, **NULLS NOT DISTINCT**) — cả hai
  `on_conflict_do_nothing` + re-select. Select-then-insert là ISSUE-017: hai tin nhắn đồng thời
  ⇒ 2 conversation ⇒ lịch sử tách đôi, KHÔNG có exception nào.
  ⚠️ `NULLS NOT DISTINCT` là bắt buộc chứ không phải tinh chỉnh: mặc định SQL coi NULL là
  distinct, mà `external_thread_id` thường NULL (Zalo không phải lúc nào cũng gửi `thread_id`)
  ⇒ UNIQUE thường sẽ cho qua cả hai row và constraint chỉ *trông như* đã vá.
- **`messages` là append-only log, KHÔNG phải hàng đợi gửi** (spec 10). Một row nghĩa là
  "việc này ĐÃ xảy ra". Ghi outbound CHỈ sau `sender.send()` thành công — ghi trước sẽ tạo
  lịch sử khai điều chưa xảy ra, và AI lượt sau tưởng đã trả lời khách rồi nên im lặng.
  Ai định viết worker drain bảng này rồi gọi sender = bypass `policy_gate`.
  ⚠️ Nhánh `park` **cố ý chưa ghi** (PRE-1004): `api/inbox.py` approve chỉ flip status, worker
  gửi CHƯA tồn tại. Hệ quả đã ký: reply seller duyệt không vào history. Mà `park` là đường
  MẶC ĐỊNH (shop chưa opt-in intent nào ⇒ mọi reply qua đó) — nên history hôm nay thiếu gần
  hết phía shop. Nhớ điều này trước khi đổ lỗi chất lượng trả lời cho prompt hay model.
- **`messages` KHÔNG idempotent** — không có khoá dedup, Zalo retry nhân đôi row. Cơ chế chống
  trùng là `webhook_event_log` (spec 03 Phase 2, BLOCKED). 🚫 Đừng vá tạm bằng select-then-insert:
  đó đúng là ISSUE-017 spec 09 vừa đóng — hai webhook đồng thời vẫn lọt cả hai, test đơn luồng
  vẫn xanh, và nó chỉ TRÔNG như đã vá.
- **TDD cho phase RISK:high:** test ĐỎ trước khi impl.

---

## 4. Config gotchas — đã trả giá, đọc trước khi đụng env

- **`.env` KHÔNG được app đọc.** `Settings` cố ý bỏ `env_file` (env_file sẽ đọc file dev cả sau `monkeypatch.delenv`). Dev nạp qua `.claude/launch.json`; production PHẢI set env tường minh. Xem `.env.example` — secret để **RỖNG**, placeholder là truthy nên sẽ trượt mọi check "đã set chưa".
- **Env rỗng = chưa set** (`_blank_env_means_unset` trong `app/config.py`). Sinh từ bug thật: `TOGETHER_MODEL=` rỗng ghi đè default ⇒ falsy ⇒ trượt `or` ⇒ xin `gpt-4o-mini` từ Together ⇒ 404.
  ✅ **Field phức nay có cặp `NoDecode` + `field_validator`** (ISSUE-018 đóng 2026-07-21). Trước đó validator chạy `mode="before"` = *sau* `EnvSettingsSource` parse JSON ⇒ `REASONING_MODELS=` rỗng làm `Settings()` **RAISE**. `NoDecode` tắt parse tầng source cho `reasoning_models` ⇒ chuỗi thô lọt tới `_blank_env_means_unset` và được coi như chưa set; `_parse_reasoning_models` tách comma khi env có giá trị. Thêm field phức thứ hai ⇒ lặp lại đúng cặp đó, đừng trông vào `_blank_env_means_unset` một mình.
- **Security path đọc `Settings()` fresh mỗi call**, KHÔNG `get_settings()` cached — né cache-staleness.
- **Chat model = `meta-llama/Llama-3.3-70B-Instruct-Turbo`.** KHÔNG đổi sang MiniMax-M3 (bịa 6/6 ca an toàn, đắt hơn 2.4× khi dùng thật — DEC-OHANA-02). **Danh sách `/v1/models` KHÔNG chứng minh model dùng được** — có model kèm bảng giá vẫn 400 "non-serverless". Đổi model xong **PHẢI** chạy `pytest tests/test_together_live.py -m live`. Cold start ~24.8s, call sau ~1.2s ⇒ UI bắt buộc có loading state.
- **`ruff` LUÔN chạy với `--no-cache`, và version bị PIN.** `.ruff_cache` do một bản ruff cũ ghi ra **không bị vô hiệu khi ruff nâng cấp**: `ruff check .` trả `All checks passed!` trong khi `ruff check . --no-cache` trả 4 lỗi trên **cùng source**. Gate local nói dối, và `GATE_FULL` của ADP nuốt lời nói dối đó vào EVIDENCE — spec 08 E0 đã bị stamp một bước ruff xanh giả trước khi phát hiện. Rà lại 22 phase DONE dưới ruff pin: **19/22 không tái lập được** `ruff check`. **CI xác nhận 2026-07-20: 19/23 run đỏ, và CI CHƯA TỪNG XANH** cho tới commit vá — mọi phase spec 04–07 đều stamp DONE trong lúc CI đỏ (ISSUE-019). Vì vậy `pyproject.toml` pin **cả 4 dev tool** — `ruff==0.15.22` · `mypy==2.3.0` · `pytest==9.1.1` · `pytest-asyncio==1.4.0` (KHÔNG `>=`) — gate phải là hàm của source, không phải của ngày cài đặt.
  Cả ba cái sau **đã trôi qua major** so với floor cũ (mypy 1.10→2.3, pytest 8.0→9.1, asyncio 0.23→1.4) — tức gate đã chạy trên major khác suốt mà không ai biết. Đo trước khi pin: mypy có/không cache cùng kết quả, pytest cùng 129 pass ⇒ pin là chốt hiện trạng, không đổi hành vi.
  ✅ **Runtime deps cũng đã pin** (2026-07-20, ISSUE-019 action 6) — 16 dep, trong đó 4 đã qua đổi MAJOR khi còn `>=`: `openai` 1.30→2.45 · `pypdf` 4→6.14 · `redis` 5→8.0 · `sse-starlette` 2.1→3.4. Nâng version: đổi số → `pytest -m live` (fake client KHÔNG bắt được lỗi SDK/endpoint) → xem CI xanh → mới commit.
- **Exclusion phải chết cùng lý do của nó.** `api/` bị loại khỏi scope mypy vì "10 lỗi
  FastAPI `Depends`" — các lỗi đó được vá dần trong spec 04–07, nhưng dòng loại trừ ở lại.
  Kết quả: `api/` có `chat.py`/`inbox.py`/`admin.py`/`webhook.py` với `shop_id` chạy qua mà
  không gate nào nhìn. ISSUE-024 (Protocol `_Drafter` lệch) sống được chính nhờ khoảng mù đó
  — cộng thêm một `# type: ignore` dán đúng lên dòng Protocol. Đo lại 2026-07-20: `api/` 0 lỗi,
  `auth/` cũng 0 lỗi. **Cả hai đã vào scope 2026-07-20 ⇒ không còn thư mục nào bị loại.**
  ⇒ Khi viết một exclusion, viết luôn điều kiện gỡ nó. Không có điều kiện thì nó là vĩnh viễn.
  ⇒ Và giờ scope đã đầy: thêm lại bất kỳ exclusion nào PHẢI kèm điều kiện gỡ đo được.
- **Embedding dim là BREAKING — đã swap sang e5 (spec 08, 2026-07-19).** Nguồn sự thật DUY NHẤT là `app/config.EMBED_DIM = 1024`; `db/models._EMBED_DIM` và `api/admin._DEV_EMBED_DIM` là **alias import**, không phải bản sao. Trước spec 08 chúng là ba số `1536` viết cứng kèm comment "must match" — comment là lời nhắc cho người, và nó đã không giữ được lời hứa.
  Đổi `EMBED_DIM` ⇒ **BẮT BUỘC** Alembic migration đổi cột + re-embed corpus. `0004` là migration destructive có chủ ý: `DELETE FROM embeddings` rồi `ALTER TYPE`. Nó có guard cơ học `_SAFE_ROW_THRESHOLD = 10` — vượt ngưỡng thì RAISE, mở bằng `OHANA_ALLOW_EMBEDDING_WIPE=1`. **`downgrade` CŨNG xoá**: reversible về schema, KHÔNG về dữ liệu.
- **e5 bất đối xứng — prefix là việc của ADAPTER, không phải call-site.** `Embedder` ABC có `embed_query`/`embed_documents` (concrete delegate, KHÔNG abstract — thêm abstract sẽ phá mọi impl cũ). `TogetherEmbedder` override cả hai để gắn `query: `/`passage: `; `OpenAIEmbedder` không cần prefix nên dùng default. Call-site chỉ khai *ý định*: `tools/wiki.py` → query, `parsing/ingest.py` → passage.
  ⚠️ **Hoán đổi prefix KHÔNG crash, KHÔNG sai type, KHÔNG đỏ test thường** — nó chỉ làm retrieval tệ đi âm thầm. Cùng họ với `_DeterministicDevEmbedder`. Vì vậy có gate bất đối xứng riêng trong `tests/test_together_embedder.py`; đừng xoá.

---

## 5. ADP workflow (v2.3, isolated tại `ohana-ai/.claude/`)

Spine quyết DONE, **KHÔNG phải LLM self-cert**. Invoke skill `adp` khi bắt đầu sprint/phase.

Manifest — **máy đọc**. `adp_manifest_get` (`.claude/hooks/adp-lib.sh`) đòi **cả 2 marker HTML comment** *và* key ở **đầu dòng**. Xoá marker hoặc gộp dòng ⇒ `adp-profile-gen.sh` FATAL, hook mất RISK_PATHS, checkpoint chết:

<!-- ADP:MANIFEST -->
GATE_RUNNER: .venv/bin/python -m pytest -q -x
RISK_PATHS: agent/orchestrator.py, agent/policy_gate.py, tools/registry.py, bridge/, auth/, db/migrations, api/webhook.py, api/inbox.py, api/admin.py, api/chat.py
SPEC_DIR: docs/tasks
ROADMAP_L1: docs/ROADMAP.md
ROADMAP_L3: docs/ROADMAP-STATUS.md
EXECUTOR_SKILL: AI-coder
CHECKPOINT_PREFIX: adp
<!-- /ADP -->

- **Checkpoint:** `adp-checkpoint.sh` stamp EVIDENCE + sinh lại L3. Không tự-certify DONE ngoài spine.
- **Mỗi phase block PHẢI có `ROADMAP: <ID>`** (trỏ `docs/ROADMAP.md §4`, đặt ngay sau `STATUS:`) **và dòng `SMOKE:`**.
- **SMOKE gate:** test đo môi trường TEST; smoke đo môi trường THẬT — không cái nào thay được cái nào. Có mặt runtime → `SMOKE: PASS ref=docs/smokes/<spec>-<phase>.md` (điền OBSERVED bằng output THẬT, không viết "OK"). Không có mặt runtime → `SMOKE: N/A <lý do ≥12 ký tự>`. **Ghi dòng SMOKE TRƯỚC khi stamp** — stamp trước rồi ghi sau ⇒ hash lệch ⇒ REFUSE (đã dính đúng bẫy này với `REVIEW:` ở spec 06 F1). Xem `.claude/tools/adp-smoke.sh`.
  Vì sao có gate: spec 07 ship 3 lỗi mà 107 test xanh + mypy 0 + 3 vòng review không thấy → `docs/memory/SHIPPED-SURFACE.md`.
- **Roadmap 3 tầng, 3 chủ:** L1 `docs/ROADMAP.md` (**người** viết) · L2 `docs/tasks/*.md` (spec, frozen) · L3 `docs/ROADMAP-STATUS.md` (**máy** sinh — không sửa tay). ⚠️ L1 nằm **NGOÀI** spec-lock có chủ ý: kéo vào vùng diff-bound = mỗi lần re-plan giữa sprint bị REFUSE vì DRIFT, tức máy cấm đổi ý. **Đừng "sửa" điều này.**
- ⚠️ **Đọc số phase DONE cho đúng (WAIVER-001, DEC-OHANA-04):** CI chưa từng xanh cho tới `01c2479` (2026-07-19). **22/25 phase DONE được ký trong lúc CI đỏ** — và vì ruff chết ở step 7 nên `mypy`/`alembic`/`pytest` **chưa từng chạy trên CI** giai đoạn đó. Với 22 phase ấy, "DONE" = *"gate local pass, CI chưa xác nhận"*. Chỉ spec 08 (E0/E1/E2) + spec 09 (C0) + spec 10 (H0/H1/H2) ký trong thời kỳ CI xanh. Code hiện tại KHÔNG bị nghi ngờ — HEAD qua đủ 11 step CI.
- **Ba bộ đếm, ba câu hỏi** (2026-07-23): `adp-status.sh` = *phase đã ký* (**38/51**) · `adp-roadmap.sh` = *work item thật* (**internal 13/36** · external 0/9) · `roadmap_dashboard.py` = *GĐ0 thôi* (**internal 12/23**). Mục tiêu 100% = mẫu số `internal`, không gộp `external`. Mẫu số **tăng** khi thêm spec/ID — % giảm là honest, không phải tiến độ xấu đi (DEC-OHANA-03). ⚠️ `adp-status` 51 vs L3 52 lệch 1 do đếm `CANCELLED` khác nhau — cả hai máy sinh, đừng "sửa" cho khớp bằng tay.
- **Isolation:** ADP v2.3 riêng, KHÔNG dùng workspace v1.3 của Onfa/DrNick. Sandbox an toàn để calibrate decision-gate (SHADOW → hard-block sau ≥5 real decision). Contract: `docs/adr/hook-contract.md`.

---

## 6. Anti-patterns

🚫 Fork nguyên `drnickv4/` — luôn port chọn lọc từng module.
🚫 Copy `db/models.py` từ DrNick — single-tenant, phải viết lại tenant-first.
🚫 Vector/DB query KHÔNG có `shop_id` scope SQL-level (post-filter = R1.22).
🚫 Đọc `user_id`/`shop_id`/`role` từ request body/webhook thay vì verified JWT.
🚫 Auto-send tới khách ngoài `policy_gate.py` — kể cả demo/dev.
🚫 Dev/placeholder fallback không gate `OHANA_ENV=="dev"` + fail-loud ngoài dev.
🚫 Skip TDD gate (RED trước impl) cho phase RISK:high.
🚫 Self-certify DONE mà không qua `adp-checkpoint.sh`.
🚫 Brief cho executor **paraphrase** scope thay vì **TRÍCH** spec block — paraphrase là chỗ scope trôi (ISSUE-012).
🚫 Sửa tay `docs/ROADMAP-STATUS.md` (L3 máy sinh), hoặc nhét changelog vào CLAUDE.md.

---

## 7. Status · nơi tra tiếp

*(tóm tắt — nguồn thật ở `docs/tasks/` + `ROADMAP-STATUS.md`)*

- ✅ **DONE:** Spec 01 (GĐ0 backend) · 02 (bootstrap) · 04 (GĐ0.5 UI) · 05 (config/embedder) · 06 (foundation) · 07 (General Chat — chạy THẬT end-to-end) · 08 (embedder swap → Together e5 1024-dim, 3/3) · 09 (unique constraint chặn race Conversation, 1/1 — đóng ISSUE-017) · 10 (conversation history — ghi + đọc `Message`, last-N vào `Drafter`, 3/3) · 11 (`shops` + `shop_profile` — persona vào prompt có cap, knowledge vào `lookup_size`/`lookup_shipping` tất định, 4/4) · 12 (wire provider-429 counter vào đường chat thật — đóng nửa còn lại ISSUE-010, 1/1) · 13 (`Drafter` — impl thật `agent.orchestrator.Drafter`, LLM adapter → draft `(text,intent,confidence)`, 2/2) · **14 (DraftSchema + Idempotency — `pending_reply` +snapshot/expires_at/label + `webhook_event_log` PK `(channel,platform_msg_id)` race-safe; KHÔNG wire runtime, 3/3)**.
- 🔄 **Spec 15 (RuntimeWiring) — 4 phase TODO, chưa bắt đầu.** De-orphan tiểu-hệ-thống outbound: P1 dọn dead code (`storage/*`, `registry.register()`) · P2 verify Tool-shape + factory · P3 dựng `LLMDrafter` trong `main.py` + integration test (**KHÔNG mount webhook** — PDPL) · P4 đóng ISSUE-026.
- ⏳ Spec 03 (acceptance backfill, 0/10, 4 BLOCKED chờ Tân) — **Phase 1 giờ là `CANCELLED`**, superseded bởi spec 11 (blocker PRE-007 ACCEPTED 2026-07-19 mà không ai gỡ; L1 `GD0-SHOPS` từng map vào HAI chủ, nay chỉ còn spec 11). Số migration cấp theo thứ tự LAND, không theo thứ tự lập kế hoạch (spec 08 lấy `0004`, spec 09 `0005`, spec 10 `0006`, spec 11 `0007`, **spec 14 lấy `0008`+`0009`**). ⚠️ **Bảng idempotency mà spec 03 Phase 2 định làm nay đã SUPERSEDED bởi spec 14 B0** (`webhook_event_log`, commit `34620c9`); sender+signature verify của spec 03 vẫn BLOCKED chờ Tân (PRE-004). Spec 03 sẽ phải renumber lại lần nữa khi land. §8 của spec 03 từng lệch với §Files của chính nó — đồng bộ 2026-07-20; xem ISSUE-021.
- **Gate hiện tại:** pytest xanh (`-m 'not live'`, **212 test**, 9 live deselected) · ruff sạch (`--no-cache`) · mypy 0 lỗi / **57 file** · `roadmap_derive verify` **26/26, 0 dangling** · `gen_codebase_map --check` xanh (re-verify 2026-07-23).
- 🔴 **CI ĐỎ ≥12 run liên tiếp (2026-07-22 → 07-23) — không ai kiểm.** Gốc: `docs/codebase-map.md` stale từ spec 13 (`agent` 11→12, `db` 13→15). **Đã vá, CI XANH tại `72b3564`** (xác minh bằng `gh run`, không suy đoán). Bài học lặp lại ISSUE-019 ở dạng mới: **gate local xanh KHÔNG chứng minh CI xanh** — `codebase-map --check` là step CHỈ CI chạy, không có trong vòng verify local. Sau mỗi đợt thêm/xoá file `.py`: chạy `python3 scripts/ai_coder/gen_codebase_map.py` rồi commit map.
- **Live (chạy tay, ngoài CI):** `test_together_live.py` 2 · `test_wiki_rag_live.py` 4 — cả 6 PASS 2026-07-19 với key thật.
- ✅ `main` đồng bộ `origin/main` (`github.com:wyattngo/ohana-ai`), tip **`72b3564`** — **CI XANH đã xác minh** (`gh run`, 2026-07-23). Branch `adp/15-Task-OhanaAISeller-RuntimeWiring` ff cùng tip.
- **Tầng gate (mới 2026-07-23):** `docs/gates/GD0-STEP1..9.md` — 9 Step ↔ 9 sub-step workflow §7, **Wyatt ký cả 9** (`approved_by: wyatt`). ⚠️ **Ký ≠ Tests đã pass**: hiện **0/40 ô test** được tick. Ký = "đúng là điều kiện tôi muốn"; đóng gate = test chạy thật. `GD0-STEP8` (DPIA) **cố ý không bind work item** — nửa external của `GD0-PII`, là điều kiện ship nhưng không vào mẫu số (option (a), Wyatt 2026-07-23).
- **Dashboard: CHỈ CÒN MỘT** — `docs/roadmap-dashboard.html`. `adp-dashboard.html` + `adp-progress-dashboard.html` đã xoá; workspace tool `adp-progress-dashboard.sh` retire vào `_archive/` (0 consumer). Click Step → Target+Tests · work item → acceptance · phase → nguyên block ADP.
- **OPEN:** ISSUE-023 (cap history 20/4000 chưa đo) · **PRE-010 — 5 ràng buộc implement** (C1 consumer idempotent · C2 scheduler `SKIP LOCKED` · C3 TTL clamp window · C4 FN-rate PII đo được · C5 severity order), nhúng sẵn vào Tests của gate tương ứng nên không thể quên · **ISSUE-026 (5 nợ RUNTIME schema spec 14 — `snapshot`/`expires_at`/`label` + `webhook_event_log` đã có cột/bảng nhưng CHƯA đường code nào ghi/đọc; cùng hình dạng "persona chưa có Drafter")**.
- **Chưa ai nhận:** rule thật của các run CI đỏ 17–18/07 (log chưa đào được) · `window_status` hết hạn có mở conversation MỚI không (constraint spec 09 sẽ chặn — phải trả lời trước `GD0-WINDOW`) · chưa có index vector (ivfflat/hnsw) cho corpus thật · worker drain `approved` rows (chặn PRE-1004/PRE-1005, và là thứ làm history đủ phía shop).
- **Blocked backfill** (chờ Tân — không chặn gate, chặn real-content): PRE-002 platform REST API spec · PRE-003 real wiki corpus · PRE-004 Zalo OA creds + webhook signature.

| Cần gì | Đọc đâu |
|---|---|
| Module ra đời ở phase nào, vì sao có hình dạng này | `docs/memory/SHIPPED-SURFACE.md` |
| Bug / nợ kỹ thuật đang mở | `docs/memory/KNOWN_ISSUES.md` |
| Quyết định đã ký + lý do | `docs/decisions/` · `docs/adr/` · `docs/memory/DECISIONS.md` |
| Session trước làm gì | `docs/memory/SESSION_LOG.md` |
| Kế hoạch (ý định) | `docs/ROADMAP.md` — L1, chỉ người viết |

---

## 8. Routing

Trigger signals: `Ohana`, `Ohana AI`, `ohana-ai`, `Zalo OA`, `seller copilot`, `Wiki RAG`, `policy_gate`, `pending_reply`, `shop_id`, `multi-tenant`, `platform_wiki`, `GĐ0 MVP`, `Tân`.

Skill: `AI-coder` (executor — Plan-Patch-Verify Python/FastAPI + AI-agent invariants; đọc `.ai-coder.conf`) · `adp-spec` (author + lint phase block v2.3, đọc manifest) · `onfa-brief-formatter` (intake brief). *(`onfa-spec-generator` KHÔNG hợp v2.3: thiếu ROADMAP/SMOKE/REVIEW/GATE_FULL, mang Survival Framework — xem đối chiếu 2026-07-21.)*

*Router level 1. Workspace router `../CLAUDE.md` (§4.7 mô tả ADP v1.3 của Onfa/DrNick). Convention thư mục `../FOLDER-CONVENTION.md`.*
