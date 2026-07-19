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
mypy app agent retrieval parsing storage db bridge tools   # strict; scope CỐ ĐỊNH (api/ auth/ OUT)
alembic upgrade head        # cần DATABASE_URL trỏ Postgres+pgvector

# Live smoke — real net, nondeterministic, KHÔNG chạy trong CI. Chạy tay khi đổi model/endpoint:
pytest -m live
pytest tests/test_together_live.py -m live   # bắt lỗi model-id/endpoint mà fake client KHÔNG thấy
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
bash .claude/tools/adp-dashboard.sh       # → docs/adp-dashboard.html (gitignored)
bash .claude/tools/adp-checkpoint.sh      # con đường DUY NHẤT để một phase thành DONE
```

CI (`.github/workflows/ci.yml`): guardrail hook → ruff lint → ruff format → mypy → alembic upgrade → pytest, trên service **Postgres (pgvector:pg16) + Redis 7 thật**. Frontend chưa có job.

---

## 2. Architecture / Layout

```
app/          FastAPI entrypoint. main.py = NƠI DUY NHẤT wire concrete deps vào router
              factory (build_*_router(...)). config.py = Settings(BaseSettings) + get_settings() lru_cache.
agent/        orchestrator · llm_client · embedder · policy_gate
  providers/  openai_client · together_client (subclass 17 dòng) · openai_embedder
channels/     base (Protocol) · identity (resolve_conversation) · zalo/ adapter
retrieval/    pgvector.py — PgvectorRetriever(shop_scope=) hard filter SQL-level
parsing/      chunk · ingest · extract (Wiki doc)
storage/      base · local
bridge/       ohana_client (REST platform API, verify=True) · zalo_sender (MockZaloSender)
auth/         identity.py — HS256 JWT (user_id, shop_id, role) · require_admin · CSRF
tools/        registry · wiki (search_wiki) · ohana_read (order_status)
api/          admin (require_admin) · inbox · mock_auth (dev-only) · chat (mounted) · webhook (CHƯA mount)
db/           models.py (tenant-first) · repos · session · migrations/ (Alembic 0001–0003)
web/          Vite+React+TS. State-based routing (KHÔNG react-router). dist/ committed.
tests/        pytest; conftest.py cung cấp fixture fresh_db (drop+create schema, dispose kể cả khi raise)
.claude/      ADP v2.3 — hooks/ (guardrail.py) + tools/ (adp-*.sh)
docs/         tasks/ (spec = L2) · ROADMAP.md (L1) · ROADMAP-STATUS.md (L3 máy sinh)
              decisions/ · adr/ · reviews/ · smokes/ · memory/ · briefs/ · archive/
```

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
- **TDD cho phase RISK:high:** test ĐỎ trước khi impl.

---

## 4. Config gotchas — đã trả giá, đọc trước khi đụng env

- **`.env` KHÔNG được app đọc.** `Settings` cố ý bỏ `env_file` (env_file sẽ đọc file dev cả sau `monkeypatch.delenv`). Dev nạp qua `.claude/launch.json`; production PHẢI set env tường minh. Xem `.env.example` — secret để **RỖNG**, placeholder là truthy nên sẽ trượt mọi check "đã set chưa".
- **Env rỗng = chưa set** (`_blank_env_means_unset` trong `app/config.py`). Sinh từ bug thật: `TOGETHER_MODEL=` rỗng ghi đè default ⇒ falsy ⇒ trượt `or` ⇒ xin `gpt-4o-mini` từ Together ⇒ 404.
  ⚠️ **Nó KHÔNG phủ complex field.** Validator chạy `mode="before"` nhưng *sau* khi `EnvSettingsSource` parse JSON ⇒ `REASONING_MODELS=` rỗng vẫn làm `Settings()` **RAISE** (`frozenset[str]`). Muốn rỗng thì **bỏ hẳn dòng**, đừng để `=` rỗng. Docstring trong code khai "áp cho MỌI field" là **sai** — ISSUE-018.
- **Security path đọc `Settings()` fresh mỗi call**, KHÔNG `get_settings()` cached — né cache-staleness.
- **Chat model = `meta-llama/Llama-3.3-70B-Instruct-Turbo`.** KHÔNG đổi sang MiniMax-M3 (bịa 6/6 ca an toàn, đắt hơn 2.4× khi dùng thật — DEC-OHANA-02). **Danh sách `/v1/models` KHÔNG chứng minh model dùng được** — có model kèm bảng giá vẫn 400 "non-serverless". Đổi model xong **PHẢI** chạy `pytest tests/test_together_live.py -m live`. Cold start ~24.8s, call sau ~1.2s ⇒ UI bắt buộc có loading state.
- **`ruff` LUÔN chạy với `--no-cache`, và version bị PIN.** `.ruff_cache` do một bản ruff cũ ghi ra **không bị vô hiệu khi ruff nâng cấp**: `ruff check .` trả `All checks passed!` trong khi `ruff check . --no-cache` trả 4 lỗi trên **cùng source**. Gate local nói dối, và `GATE_FULL` của ADP nuốt lời nói dối đó vào EVIDENCE — spec 08 E0 đã bị stamp một bước ruff xanh giả trước khi phát hiện. Rà lại 22 phase DONE dưới ruff pin: **19/22 không tái lập được** `ruff check` (ISSUE-019). Vì vậy `pyproject.toml` pin `ruff==0.15.22` (KHÔNG `>=`) — gate phải là hàm của source, không phải của ngày cài đặt. ⚠️ `mypy>=1.10` và `pytest>=8.0` **vẫn chưa pin** — cùng lớp rủi ro, chưa ai nhận.
- **Embedding dim là BREAKING:** `db/models.py` `_EMBED_DIM = 1536` → `Vector(_EMBED_DIM)`. ADR 2026-07-18 chốt chuyển OpenAI `text-embedding-3-small` (1536) → Together `intfloat/multilingual-e5-large-instruct` (1024): cần Alembic migration đổi dim + re-embed corpus. e5 cần prefix `query:` / `passage:` — mà `Embedder` ABC hiện **không phân biệt query vs passage** (`tools/wiki.py` embed query, `parsing/ingest.py` embed passage, cùng một `embed()`). Spec 08 sửa ABC trước.

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
EXECUTOR_SKILL: drnick-coder
CHECKPOINT_PREFIX: adp
<!-- /ADP -->

- **Checkpoint:** `adp-checkpoint.sh` stamp EVIDENCE + sinh lại L3. Không tự-certify DONE ngoài spine.
- **Mỗi phase block PHẢI có `ROADMAP: <ID>`** (trỏ `docs/ROADMAP.md §4`, đặt ngay sau `STATUS:`) **và dòng `SMOKE:`**.
- **SMOKE gate:** test đo môi trường TEST; smoke đo môi trường THẬT — không cái nào thay được cái nào. Có mặt runtime → `SMOKE: PASS ref=docs/smokes/<spec>-<phase>.md` (điền OBSERVED bằng output THẬT, không viết "OK"). Không có mặt runtime → `SMOKE: N/A <lý do ≥12 ký tự>`. **Ghi dòng SMOKE TRƯỚC khi stamp** — stamp trước rồi ghi sau ⇒ hash lệch ⇒ REFUSE (đã dính đúng bẫy này với `REVIEW:` ở spec 06 F1). Xem `.claude/tools/adp-smoke.sh`.
  Vì sao có gate: spec 07 ship 3 lỗi mà 107 test xanh + mypy 0 + 3 vòng review không thấy → `docs/memory/SHIPPED-SURFACE.md`.
- **Roadmap 3 tầng, 3 chủ:** L1 `docs/ROADMAP.md` (**người** viết) · L2 `docs/tasks/*.md` (spec, frozen) · L3 `docs/ROADMAP-STATUS.md` (**máy** sinh — không sửa tay). ⚠️ L1 nằm **NGOÀI** spec-lock có chủ ý: kéo vào vùng diff-bound = mỗi lần re-plan giữa sprint bị REFUSE vì DRIFT, tức máy cấm đổi ý. **Đừng "sửa" điều này.**
- **Hai bộ đếm, hai câu hỏi:** `adp-status.sh` = *phase đã ký* (21/34) · `adp-roadmap.sh` = *work item thật* (internal 8/25). Mục tiêu 100% = mẫu số `internal`, không gộp `external` chờ bên thứ ba. Số roadmap thấp hơn vì mẫu số ĐÚNG hơn — không phải tiến độ xấu đi (DEC-OHANA-03).
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

- ✅ **DONE:** Spec 01 (GĐ0 backend) · 02 (bootstrap) · 04 (GĐ0.5 UI) · 05 (config/embedder) · 06 (foundation) · 07 (General Chat — chạy THẬT end-to-end: seller login → Chat → Together trả lời).
- ⏳ Spec 03 (acceptance backfill, 0/10, 4 BLOCKED chờ Tân) · Spec 08 (embedder swap → e5, 0/3).
- **Gate hiện tại:** pytest xanh (`-m 'not live'`, 109 test) · ruff sạch · mypy 0 lỗi trên scope cố định.
- `main` == `origin/main` (`github.com:wyattngo/ohana-ai`). STATE_HASH `d61ee0d167e0` @ spec 07 G2.
- **OPEN:** ISSUE-010 (alerting) · ISSUE-016 (live embedding chưa nghiệm thu với e5) · ISSUE-017 (`channels/identity.py` thiếu unique `(shop_id, customer_id, channel)` — PHẢI thêm trước khi Spec 03c mount webhook) · ISSUE-018 (blank-env không phủ complex field).
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

Skill: `drnick-coder` (Plan-Patch-Verify Python/FastAPI) · `onfa-spec-generator` (thêm spec phase) · `onfa-brief-formatter` (intake brief).

*Router level 1. Workspace router `../CLAUDE.md` (§4.7 mô tả ADP v1.3 của Onfa/DrNick). Convention thư mục `../FOLDER-CONVENTION.md`.*
