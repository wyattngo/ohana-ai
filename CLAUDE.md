# CLAUDE.md — Ohana AI Seller

AI copilot cho seller social-commerce VN (Zalo/FB/IG). **MVP Zalo-only.** Python 3.11 /
FastAPI / PostgreSQL + pgvector / Alembic backend; Vite + React 19 + TS frontend (`web/`).

- **Ưu tiên**: safety → user trust → stability → growth (KHÔNG dùng fintech Survival Framework).
- **Multi-tenant is the core invariant**: mọi dữ liệu scope theo `shop_id` ở tầng SQL.
- Owner: Tân (dev) · Approver: Wyatt Ngo (CTO). Fork chọn lọc từ `drnickv4/` — KHÔNG fork nguyên repo.

> Đây là entrypoint chuẩn. Lịch sử thay đổi chi tiết + trạng thái sống nằm ở
> `docs/tasks/*.md` (specs), `docs/ROADMAP.md` (ý định), `docs/ROADMAP-STATUS.md` (máy sinh),
> `docs/memory/{SESSION_LOG,DECISIONS,KNOWN_ISSUES}.md`. Đừng nhét changelog vào file này.

---

## Commands

Backend (dùng `.venv/bin/…` nếu có venv; CI dùng `pip install -e ".[dev]"`):

```bash
pytest -q                       # default gate — live tests bị loại (addopts: -m 'not live')
pytest -q -x                    # gate của ADP (GATE_RUNNER), dừng ở lỗi đầu
ruff check .                    # lint (E,F,I,B,UP,S — bao gồm bandit S)
ruff format --check .           # format check
mypy app agent retrieval parsing storage db bridge tools   # strict; scope CỐ ĐỊNH này (api/auth OUT — xem KNOWN_ISSUES)
alembic upgrade head            # migrate; cần DATABASE_URL trỏ Postgres+pgvector

# Live smoke — real net, nondeterministic, KHÔNG chạy trong CI. Chạy tay khi đổi model/endpoint:
pytest -m live                                    # tất cả live
pytest tests/test_together_live.py -m live        # bắt lỗi model-id/endpoint mà fake client KHÔNG thấy
```

Frontend (`web/`) — **Node ≥ 20 bắt buộc**, dùng pnpm:

```bash
cd web && pnpm install && pnpm build     # → web/dist/ (COMMITTED — chưa có CI Node step)
pnpm dev                                 # vite dev server
pnpm lint                                # oxlint
```

CI (`.github/workflows/ci.yml`): guardrail hook → ruff lint → ruff format → mypy → alembic
upgrade → pytest, trên Postgres(pgvector) + Redis service thật. Frontend chưa có job.

---

## Architecture / Layout

```
app/          FastAPI entrypoint. main.py = NƠI DUY NHẤT wire concrete deps vào router factories.
              config.py = Settings(BaseSettings) + get_settings() lru_cache.
agent/        orchestrator · llm_client · embedder · policy_gate
  providers/  openai_client · together_client (subclass 17 dòng) · openai_embedder
channels/     base (Protocol) · identity (resolve_conversation) · zalo/ adapter
retrieval/    pgvector.py — PgvectorRetriever(shop_scope=) hard filter SQL-level
parsing/      chunk · ingest · extract (Wiki doc)
storage/      base · local
bridge/       ohana_client (REST platform API, verify=True) · zalo_sender (MockZaloSender)
auth/         identity.py — HS256 JWT (user_id, shop_id, role), require_admin, CSRF
tools/        registry · wiki (search_wiki) · ohana_read (order_status)
api/          admin (require_admin) · inbox · mock_auth (dev-only) · chat (mounted) · webhook (CHƯA mount)
db/           models.py (tenant-first) · repos · session · migrations/ (Alembic 0001–0003)
web/          Vite+React+TS. State-based routing (KHÔNG react-router). dist/ committed.
tests/        pytest; conftest.py cung cấp fixture fresh_db (drop+create schema).
.claude/      ADP v2.3 — hooks/ (guardrail.py) + tools/ (adp-*.sh)
docs/         tasks/ (specs=L2) · ROADMAP.md (L1) · ROADMAP-STATUS.md (L3 máy sinh)
              decisions/ · adr/ · reviews/ · smokes/ · memory/
```

**Mount order (app/main.py)**: mọi `/api/*` router include TRƯỚC `StaticFiles(web/dist)` ở `/`
— static là catch-all, mount trước sẽ che hết `/api/*`.

**inbox vs chat**: `api/inbox.py` = seller duyệt reply GỬI KHÁCH (qua policy_gate). `api/chat.py`
= seller ↔ AI nội bộ (General Chat), KHÔNG tới khách.

---

## Safety rules — KHÔNG vi phạm

Đây là các bất biến bảo mật, guardrail hook (`.claude/hooks/guardrail.py`) chặn cơ học một phần:

- **Tenant scope**: mọi vector/DB query PHẢI có `shop_id` scope ở tầng SQL. Post-filter = vi phạm
  R1.22. Composite FK `(shop_id, child_id)` để Postgres từ chối cross-tenant row.
- **Identity từ JWT, KHÔNG từ body/webhook**: đọc `user_id`/`shop_id`/`role` từ verified JWT.
  `ChatIn` dùng `extra="ignore"` → body khai `shop_id` bị bỏ.
- **KHÔNG auto-send tới khách ngoài `policy_gate.py`** — kể cả demo/dev. Intent nhạy cảm
  (complaint/refund/price_negotiation/specific_order) KHÔNG bao giờ auto-send.
- **HTTP client KHÔNG `verify=False`** trong prod (guardrail deny).
- **Dev/placeholder fallback (secret, embedder, sender, mock) PHẢI gate trên `OHANA_ENV=="dev"`
  và fail-LOUD ngoài dev.** Docstring "NOT production-safe" KHÔNG làm nó an toàn. Đã dính 2 lần:
  - `get_jwt_secret()`: fallback literal → attacker forge cookie `shop_id` bất kỳ = cross-tenant.
  - `_DeterministicDevEmbedder`: vector giả → `search_wiki` trả chunk gần-ngẫu-nhiên → AI trả
    lời sai KHÔNG stack trace (silent-wrong tệ hơn crash).
- **TDD cho phase RISK:high**: test ĐỎ trước khi impl.

---

## Config gotchas (đã trả giá — đọc trước khi đụng env)

- **`.env` KHÔNG được app đọc** (`Settings` cố ý bỏ `env_file`). Dev nạp qua `.claude/launch.json`;
  production PHẢI set env tường minh. Xem `.env.example` cho toàn bộ field + ghi chú bảo mật.
- **Env rỗng = chưa set** (`_blank_env_means_unset`, áp cho MỌI field). Sinh từ bug thật:
  `TOGETHER_MODEL=` rỗng ghi đè default → falsy → xin `gpt-4o-mini` từ Together → 404.
- **`REASONING_MODELS=` rỗng làm Settings() RAISE** (frozenset field, parse JSON). Muốn rỗng thì
  BỎ HẲN dòng, đừng để `=` rỗng.
- **Chat model = `meta-llama/Llama-3.3-70B-Instruct-Turbo`**. KHÔNG đổi sang MiniMax-M3 (bịa 6/6 ca
  an toàn, đắt hơn 2.4×). Danh sách `/v1/models` KHÔNG chứng minh model dùng được (có model kèm giá
  vẫn 400 "non-serverless"). Đổi model xong PHẢI chạy `pytest tests/test_together_live.py -m live`.
  Cold start ~24.8s, call sau ~1.2s → UI bắt buộc có loading state.
- **Embedding dim là BREAKING**: `db/models.py` khoá `Vector(1536)`. ADR 2026-07-18 chốt chuyển
  OpenAI `text-embedding-3-small` (1536) → Together `intfloat/multilingual-e5-large-instruct`
  (1024) — cần Alembic migration đổi dim + re-embed corpus. e5 cần prefix `query:`/`passage:`.

---

## ADP workflow (v2.3, isolated tại `ohana-ai/.claude/`)

Project dùng ADP để gate phase — spine quyết DONE, KHÔNG phải LLM self-cert. Invoke skill `adp`
khi bắt đầu sprint/phase.

**Manifest (máy đọc — `adp_manifest_get` parse `KEY:` trong block dưới; ĐỪNG đổi format/xoá markers):**

<!-- ADP:MANIFEST -->
GATE_RUNNER: .venv/bin/python -m pytest -q -x
RISK_PATHS: agent/orchestrator.py, agent/policy_gate.py, tools/registry.py, bridge/, auth/, db/migrations, api/webhook.py, api/inbox.py, api/admin.py, api/chat.py
SPEC_DIR: docs/tasks
ROADMAP_L1: docs/ROADMAP.md
ROADMAP_L3: docs/ROADMAP-STATUS.md
EXECUTOR_SKILL: drnick-coder
CHECKPOINT_PREFIX: adp
<!-- /ADP -->

- **Checkpoint**: `bash .claude/tools/adp-checkpoint.sh` stamp EVIDENCE + sinh lại L3 roadmap.
  KHÔNG tự-certify DONE ngoài spine.
- **Mỗi phase block PHẢI có** dòng `ROADMAP: <ID>` (trỏ `docs/ROADMAP.md §4`) và `SMOKE:` line.
- **SMOKE gate**: test đo môi trường TEST; smoke đo môi trường THẬT — không thay được nhau. Phase
  có mặt runtime → `SMOKE: PASS ref=docs/smokes/<spec>-<phase>.md` (điền OBSERVED bằng output
  THẬT). Phase không runtime → `SMOKE: N/A <lý do ≥12 ký tự>`. Ghi dòng SMOKE **trước** khi stamp
  (stamp trước → hash lệch → REFUSE). Xem `.claude/tools/adp-smoke.sh`.
- **Roadmap 3 tầng, 3 chủ**: L1 `docs/ROADMAP.md` (người viết) · L2 `docs/tasks/*.md` (spec,
  frozen) · L3 `docs/ROADMAP-STATUS.md` (máy sinh `adp-roadmap.sh` — KHÔNG sửa tay). L1 nằm NGOÀI
  spec-lock có chủ ý.
- Trạng thái: `bash .claude/tools/adp-status.sh` (phase đã ký) vs
  `bash .claude/tools/adp-roadmap.sh "$PWD"` (kế hoạch đã phủ) — hai câu hỏi khác nhau.

---

## Status (tóm tắt — nguồn thật ở docs/tasks + ROADMAP-STATUS.md)

- ✅ DONE: Spec 01 (GĐ0 backend) · 02 (bootstrap) · 04 (GĐ0.5 UI) · 05 (config/embedder) ·
  06 (foundation) · 07 (General Chat — chạy THẬT end-to-end: seller login → Chat → Together trả lời).
- ⏳ Spec 03 (acceptance backfill, 0/10, 4 BLOCKED chờ Tân) · Spec 08 (embedder swap → e5, 0/3).
- **OPEN issues**: ISSUE-010 (alerting), ISSUE-016 (live embedding chưa nghiệm thu với e5),
  ISSUE-017 (`channels/identity.py` thiếu unique `(shop_id, customer_id, channel)` — PHẢI thêm
  trước khi Spec 03c mount webhook).
- Gate hiện tại: pytest xanh (`-m 'not live'`), ruff sạch, mypy 0 lỗi trên scope cố định.

**Blocked backfill (chờ Tân — không chặn gate, chặn real-content):**
- PRE-002: Ohana platform REST API spec (order_status hiện là MockTransport contract).
- PRE-003: real Wiki docs corpus (ingest chạy, chưa có nội dung thật).
- PRE-004: Zalo OA creds + webhook signature + rate-limit (`MockZaloSender`, webhook chưa mount).

---

## Anti-patterns

🚫 Fork nguyên `drnickv4/` — luôn port chọn lọc từng module.
🚫 Copy `db/models.py` từ DrNick — single-tenant, phải viết lại tenant-first.
🚫 Vector/DB query KHÔNG có `shop_id` scope SQL-level (post-filter = R1.22).
🚫 Đọc `user_id`/`shop_id`/`role` từ request body/webhook thay vì verified JWT.
🚫 Auto-send tới khách ngoài `policy_gate.py` — kể cả demo/dev.
🚫 Dev/placeholder fallback KHÔNG gate trên `OHANA_ENV=="dev"` + fail-loud ngoài dev.
🚫 Skip TDD gate (RED trước impl) cho phase RISK:high.
🚫 Self-certify DONE mà không qua `adp-checkpoint.sh`.
🚫 Brief cho executor paraphrase scope thay vì TRÍCH spec block — paraphrase là chỗ scope trôi.
🚫 Sửa tay `docs/ROADMAP-STATUS.md` (L3 máy sinh) hoặc nhét changelog vào CLAUDE.md.
