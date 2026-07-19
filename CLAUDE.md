# CLAUDE.md — Ohana AI Seller

AI copilot cho seller social-commerce VN (Zalo/FB/IG). GĐ0 MVP, Zalo-only, 3–4 tuần.
Sub-project của workspace `localhost/` — router level 0 tại `../CLAUDE.md`.

**Owner:** Tân (dev lead) · **Approver:** Wyatt Ngo (fractional CTO)
**Priority order:** safety → user trust → stability → growth *(KHÔNG dùng fintech Survival Framework)*

---

## 1. Lệnh

Node ≥ 20 bắt buộc — system default trên máy Wyatt là v16. `nvm use v23.6.1` trước mọi lệnh pnpm.

```bash
# Gate chính (đúng lệnh mà stop-gate hook chạy — đừng tự thuật "passed")
.venv/bin/python -m pytest -q -x

# Live gate — real-net, bị addopts loại khỏi CI, PHẢI chạy tay.
# Đây là lớp DUY NHẤT bắt được lỗi model-id/endpoint mà fake client không thấy.
pytest tests/test_together_live.py -m live

# Lint / type (khớp ci.yml)
ruff check . && ruff format --check .
mypy app agent retrieval parsing storage db bridge tools

# DB
alembic upgrade head

# Web
nvm use v23.6.1 && cd web && pnpm install && pnpm build   # → web/dist/ (COMMITTED, chưa có CI Node step)

# ADP
bash .claude/tools/adp-status.sh              # phase đã ký tới đâu
bash .claude/tools/adp-roadmap.sh "$PWD"      # kế hoạch phủ tới đâu (sinh lại L3)
bash .claude/tools/adp-dashboard.sh           # → docs/adp-dashboard.html (gitignored)
bash .claude/tools/adp-checkpoint.sh          # con đường DUY NHẤT để một phase thành DONE
```

**Hai bộ đếm, hai câu hỏi khác nhau — đừng lẫn.** `adp-status` đếm *phase đã ký* (21/34); `adp-roadmap` đếm *work item thật* (internal 8/25). Số roadmap thấp hơn vì mẫu số ĐÚNG hơn, không phải vì tiến độ xấu đi — xem DEC-OHANA-03.

---

## 2. Kiến trúc

Python 3.11 / FastAPI / PostgreSQL + pgvector / Alembic — **fork chọn lọc từ `drnickv4/`**, KHÔNG fork nguyên repo. Redis chưa wire.
Web: Vite 8 + React 19 + TypeScript + pnpm + lucide-react (DEC-OHANA-01 §U1).

```
app/          FastAPI entrypoint — mount order quan trọng (§3)
agent/        orchestrator · llm_client · embedder · policy_gate
  providers/  openai_client.py · together_client.py   ← KHÔNG phải top-level providers/
channels/     base.py (Protocol) · identity.py (channel,external_id → ids nội bộ) · zalo/
retrieval/    pgvector wrapper — shop_id-scoped
parsing/      Wiki doc chunker
storage/      Storage abstractions
bridge/       ohana_client.py (REST platform API) · zalo_sender.py
auth/         identity + jwt (multi-tenant)
tools/        registry.py · wiki.py (search_wiki) · ohana_read.py
api/          admin.py · inbox.py · mock_auth.py · chat.py · webhook.py
db/           models.py (tenant-first) · migrations/ (Alembic)
web/src/      App.tsx (state-based routing, KHÔNG react-router) · lib/ · screens/
tests/
docs/         ROADMAP.md (L1) · ROADMAP-STATUS.md (L3) · tasks/ (L2) · adr/ ·
              decisions/ · reviews/ · smokes/ · memory/ · briefs/ · archive/
```

**`inbox.py` vs `chat.py` — đừng lẫn.** `inbox` = duyệt reply **gửi khách**. `chat` = seller ↔ AI **nội bộ**, không bao giờ tới khách. Ranh giới này có gate import-graph: `api/chat.py` chạm sender / `PendingReply` / `agent.policy_gate` là ĐỎ.

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

**KHÔNG port:** `bridge/onfa_client.py`, `tools/onfa_actions.py`, `pending_action` financial logic, ConfirmEvent 2FA path.

---

## 3. Ràng buộc runtime (dễ vỡ, khó thấy)

- **Mount order trong `app/main.py`**: `StaticFiles(web/dist)` ở `/` là catch-all — **mount CUỐI**. Mount trước sẽ che toàn bộ `/api/*`. Đang mount: `/api/inbox` (3 route) · `/api/mock/authorize` (dev-only guard `OHANA_ENV=="dev"`) · `/api/admin/wiki/ingest` (`require_admin`) · `/api/chat`.
- **`api/webhook.py` CHƯA mount** (thiếu concrete `Drafter` impl). Trước khi mount: phải thêm unique `(shop_id, customer_id, channel)` ở `channels/identity.py` — ISSUE-017.
- **`.env` KHÔNG được app đọc.** `Settings` cố ý bỏ `env_file`. Dev nạp qua `.claude/launch.json`; production PHẢI set env tường minh. Trong `.env.example` để secret **RỖNG** — placeholder là truthy, sẽ trượt qua mọi check "đã set chưa".
- **Env rỗng = chưa set** (`_blank_env_means_unset` trong `app/config.py`, áp cho MỌI field). Sinh ra từ bug thật: `TOGETHER_MODEL=` rỗng ghi đè default → falsy → trượt `or` → gọi Together bằng model id OpenAI → 404.
- **Security path đọc `Settings()` fresh mỗi call**, KHÔNG `get_settings()` cached — né cache-staleness.
- **`tests/conftest.py` có fixture `fresh_db`** (drop+create schema, dispose kể cả khi test raise). Test DB mới dùng nó, KHÔNG tự dựng engine.
- **Model chat = `meta-llama/Llama-3.3-70B-Instruct-Turbo`.** KHÔNG đổi sang MiniMax-M3 dù rẻ hơn 3.5× trên bảng giá — bịa 6/6 lần ở ca an toàn, đắt hơn 2.4× khi dùng thật (DEC-OHANA-02).
- **Cold start 24.8s**, call sau ~1.2s ⇒ UI bắt buộc có loading state.

---

## 4. ADP Manifest

<!-- ADP:MANIFEST -->
GATE_RUNNER: .venv/bin/python -m pytest -q -x
RISK_PATHS: agent/orchestrator.py, agent/policy_gate.py, tools/registry.py, bridge/, auth/, db/migrations, api/webhook.py, api/inbox.py, api/admin.py, api/chat.py
SPEC_DIR: docs/tasks
ROADMAP_L1: docs/ROADMAP.md
ROADMAP_L3: docs/ROADMAP-STATUS.md
EXECUTOR_SKILL: drnick-coder
CHECKPOINT_PREFIX: adp
<!-- /ADP -->

**Isolation:** Ohana dùng ADP v2.3 riêng (`ohana-ai/.claude/`), KHÔNG dùng workspace v1.3 của Onfa/DrNick. Đây là sandbox an toàn để calibrate decision-gate (SHADOW → hard-block sau ≥5 real decision). Contract chi tiết: `docs/adr/hook-contract.md` + `MODEL.md` bundle export. Workspace router `../CLAUDE.md §4.7` mô tả v1.3 flow (áp dụng Onfa/DrNick).

### Ba tầng roadmap, ba chủ sở hữu — đừng trộn (DEC-OHANA-03)

| Tầng | File | Ai viết | Sửa khi nào |
|---|---|---|---|
| L1 | `docs/ROADMAP.md` | **người** | đổi ý định/kế hoạch |
| L2 | `docs/tasks/*.md` | senior-engineer → frozen | mở spec mới |
| L3 | `docs/ROADMAP-STATUS.md` | **máy** — `adp-roadmap.sh` | không bao giờ sửa tay |

Mỗi ADP phase block PHẢI có `ROADMAP: <ID>` trỏ về một ID trong `docs/ROADMAP.md §4`, đặt ngay sau `STATUS:`.

`adp-checkpoint.sh` tự sinh lại L3 sau khi stamp EVIDENCE. **Checkpoint KHÔNG ghi vào L1** — L1 là tầng ý định, chỉ người viết.

⚠️ **L1 nằm NGOÀI spec-lock có chủ ý.** `adp_spec_lock_verify` chỉ khoá `SPEC_DIR`. Kéo L1 vào vùng diff-bound = mỗi lần re-plan giữa sprint bị checkpoint REFUSE vì DRIFT, tức máy cấm đổi ý. **Đừng "sửa" điều này.**

**Mục tiêu 100% = mẫu số `internal`** (không gộp `external` chờ bên thứ ba, không gộp GĐ4). L3 phát hiện drift hai chiều: `uncovered` (mục roadmap chưa spec nào nhận) + `unplanned` (phase làm ngoài kế hoạch).

### SMOKE gate (bắt buộc từ 2026-07-19)

Mỗi ADP phase block PHẢI có dòng `SMOKE:`. `adp-checkpoint.sh` REFUSE nếu thiếu.

```
SMOKE: PASS ref=docs/smokes/<spec>-<phase>.md    # có mặt runtime
SMOKE: N/A <lý do cụ thể, ≥12 ký tự>             # không có mặt runtime
```

**Vì sao:** spec 07 ship 3 lỗi mà 107 test xanh + mypy 0 + 3 vòng review đều không thấy, cộng 2 lỗi layout không test nào có khả năng thấy (repo không có Playwright). Chi tiết từng lỗi: [SHIPPED-SURFACE.md](docs/memory/SHIPPED-SURFACE.md) §"Vì sao spec 07 đẻ ra SMOKE gate".
**Mẫu chung: test đo môi trường TEST; smoke đo môi trường THẬT.** Không cái nào thay được cái nào.

**Thứ tự thao tác — đừng đảo bước 3–4:**
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

---

## 5. Anti-patterns

🚫 Auto-send tới khách KHÔNG qua `policy_gate.py` — kể cả demo/dev.
🚫 Intent nhạy cảm (complaint / refund / price_negotiation / specific_order) auto-send.
🚫 Vector query hoặc DB query KHÔNG include `shop_id` scope **SQL-level** (post-filter = R1.22 violation).
🚫 Đọc `user_id` / `shop_id` / `role` từ request body hoặc webhook payload thay vì verified JWT.
🚫 Fork nguyên `drnickv4/` repo — luôn port chọn lọc. Copy `db/models.py` từ DrNick (single-tenant).
🚫 Skip TDD gate (test ĐỎ trước khi impl) cho phase RISK: high.
🚫 Self-certify DONE mà không qua `adp-checkpoint.sh` — spine quyết, không phải LLM.

🚫 **Dev/placeholder fallback (secret, embedder, sender, mock) KHÔNG gate trên `OHANA_ENV == "dev"`.** Fallback phải fail-LOUD ngoài dev. Docstring `"NOT production-safe"` KHÔNG làm nó an toàn — nó chỉ chứng minh tác giả biết mà vẫn để đó. Đã dính 2 lần trong spec 04 (JWT secret công khai → cross-tenant bypass; dev embedder → AI trả lời khách sai, không stack trace). Nếu một fallback chỉ đúng ở dev, gate nó trên cùng tín hiệu dev — **và test cái gate đó**. Chi tiết: [SHIPPED-SURFACE.md](docs/memory/SHIPPED-SURFACE.md) §"Hai lần dính dev-fallback".

🚫 **Brief cho executor tự liệt kê lại scope thay vì TRÍCH spec.** Brief phải **quote** spec block, không paraphrase — paraphrase là chỗ scope trôi (ISSUE-012).

---

## 6. Trạng thái · nơi tra tiếp

- ✅ Spec 01 (5/5) · 02 (4/4) · 04 (3/3) · 05 (3/3) · 06 (3/3) · 07 (3/3)
  ⏳ Spec 03 = 0/10 (4 BLOCKED, chờ Tân) · Spec 08 = 0/3
- Test suite **109 test, 0 xfail, 3 deselected (`-m live`)** · ruff sạch · **mypy 0 lỗi / 37 file**
- `main` == `origin/main` (`github.com:wyattngo/ohana-ai`), đã push. STATE_HASH `d61ee0d167e0` @ spec 07 G2.
- **General Chat chạy THẬT end-to-end**: seller login → màn Chat → Together trả lời, có auth + CSRF + observability.

**OPEN blockers:** ISSUE-010 (alerting) · ISSUE-016 (live acceptance phải chạy trên e5 1024-dim, không phải OpenAI 1536) · ISSUE-017 (unique constraint trước khi mount webhook).
**Chờ Tân (backfill, không chặn gate):** PRE-002 platform API spec · PRE-003 wiki corpus · PRE-004 Zalo OA creds.

| Cần gì | Đọc đâu |
|---|---|
| Module này ra đời ở phase nào, vì sao có hình dạng này | `docs/memory/SHIPPED-SURFACE.md` |
| Bug/nợ kỹ thuật đang mở | `docs/memory/KNOWN_ISSUES.md` |
| Quyết định đã ký + lý do | `docs/decisions/` · `docs/adr/` · `docs/memory/DECISIONS.md` |
| Session trước làm gì | `docs/memory/SESSION_LOG.md` |
| Kế hoạch (ý định) | `docs/ROADMAP.md` — L1, chỉ người viết |

---

## 7. Routing

Trigger signals: `Ohana`, `Ohana AI`, `ohana-ai`, `Zalo OA`, `seller copilot`, `Wiki RAG`, `policy_gate`, `pending_reply`, `shop_id`, `multi-tenant`, `platform_wiki`, `GĐ0 MVP`, `Tân`.

Skill: `drnick-coder` (Plan-Patch-Verify Python/FastAPI) · `onfa-spec-generator` (thêm spec phase) · `onfa-brief-formatter` (intake brief).

*Router level 1. Workspace router `../CLAUDE.md`. Convention thư mục `../FOLDER-CONVENTION.md`.*
