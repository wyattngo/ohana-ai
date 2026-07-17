# KNOWN_ISSUES — Ohana AI Seller

> Nơi log deferred bugs / assumption breaks / waivers / open PRE checks. Update mỗi sub-phase (ghi mới, KHÔNG xoá cũ — chỉ đổi STATUS + gắn resolved commit SHA).
>
> Last updated: 2026-07-17 · Status: Spec 01 = 100% DONE. Contract gates all GREEN via mocks/fixtures; PRE-002/003/004 backfill deferred until source landed. Newly-tracked deferred items from Phase 2–5: HS256+exp/aud/iss upgrade (auth), send-on-approve worker (F3), shops/customers/conversations tables, wider F2 read-tools.

---

## Format entry

```
### ISSUE-NNN — <one-line title>
- **Origin:** <spec §|PRE-N|phase-X.Y|drnickv4 port|external>
- **Discovered:** <YYYY-MM-DD> · session <ref>
- **Severity:** critical | high | medium | low
- **Status:** OPEN | BLOCKED (waiting <who>) | DEFERRED (phase <N>) | RESOLVED (<sha>)
- **Detail:** <what breaks / what's unclear>
- **Action:** <who does what next>
```

---

## Open — PRE checks blocking Phase 1.0

### ISSUE-001 — PRE-005 chưa Wyatt lock channel Zalo OA
- **Origin:** spec 01 §6 PRE-005
- **Discovered:** 2026-07-16
- **Severity:** high (block Sub-task D/E)
- **Status:** BLOCKED (waiting Wyatt)
- **Detail:** Memory note "recommended Zalo-first" nhưng Wyatt chưa confirm official. Nếu FB/Meta first → bridge target đổi, Phase 4 spec phải rewrite.
- **Action:** Wyatt confirm bằng 1 dòng trong DECISIONS.md.

### ISSUE-002 — PRE-006 cardinality tenant chưa quyết
- **Origin:** CLAUDE.md §8 PRE-006
- **Discovered:** 2026-07-16
- **Severity:** critical (block Phase 2 tenant-first models)
- **Status:** BLOCKED (waiting Wyatt)
- **Detail:** `shop_id` đủ, hay cần cả `seller_id`/`tenant_id` (1 seller nhiều shop)? Sai schema đầu Phase 2 = R1.22 analog (multi-tenancy retrofit rủi ro cao nhất).
- **Action:** Wyatt quyết dứt khoát trước Phase 2 kick-off. Ghi vào DECISIONS.md kèm rationale.

### ISSUE-003 — PRE-002/003/004 chờ Tân
- **Origin:** spec 01 §6
- **Discovered:** 2026-07-16
- **Severity:** high (PRE-002 block F2; PRE-003 block F1; PRE-004 block F3 send-leg)
- **Status:** BLOCKED (waiting Tân)
- **Detail:**
  - PRE-002: Ohana platform REST API spec (order/shipping/product/account endpoints + auth)
  - PRE-003: Wiki docs source (Notion/Drive/markdown) + format
  - PRE-004: Zalo OA credentials + webhook contract + rate-limit 48h/8-msg confirm
- **Action:** Tân bàn giao 3 gói này TRƯỚC Phase 3. Phase 1 vẫn chạy được (không depend).

### ISSUE-004 — PRE-001 db/models.py drnickv4 chưa audit
- **Origin:** spec 01 §6 PRE-001 (đã restate ở spec 02 PRE-102)
- **Discovered:** 2026-07-16
- **Severity:** medium (ảnh hưởng scope Phase 2 rewrite, không block Phase 1)
- **Status:** DEFERRED (Phase 1.0 Discovery sẽ run)
- **Detail:** Cần grep `shop_id|tenant_id|__tablename__` trong drnickv4/db/models.py để biết có scaffold tenant sẵn không. Nếu có → giảm scope rewrite.
- **Action:** Session sau chạy Phase 1.0, kết quả ghi vào PHASE1_DISCOVERY.md.

---

## Assumptions unverified (spec 02 §Assumptions & Open)

### ISSUE-005 — Guardrail location trong drnickv4
- **Origin:** spec 02 PRE-103
- **Severity:** medium (nếu ở `.claude/skills/` thay vì `.claude/hooks/` → adapt port pattern)
- **Status:** DEFERRED (Phase 1.0 sẽ verify)
- **Action:** `find drnickv4/.claude -name "guardrail*" -type f`. Nếu 0 hit → STOP hỏi Wyatt (spec 01 §5 assume tồn tại).

### ISSUE-006 — Reviewer subagent — user-level đủ hay cần port custom
- **Origin:** spec 02 PRE-104
- **Severity:** low
- **Status:** DEFERRED (Phase 1.0)
- **Action:** `ls drnickv4/.claude/agents/` — nếu empty và `~/.claude/agents/` đã có 6 v2.3 agents → skip port.

### ISSUE-007 — CI workflow có tồn tại trong drnickv4 không
- **Origin:** spec 02 PRE-105
- **Severity:** low
- **Status:** DEFERRED (Phase 1.0)
- **Action:** `ls drnickv4/.github/workflows/`. Nếu empty → gắn TODO Phase 1.4, không block.

### ISSUE-008 — Alembic có sẵn trong drnickv4 không
- **Origin:** spec 02 PRE-106
- **Severity:** low
- **Status:** DEFERRED (Phase 1.0)
- **Action:** `test -f drnickv4/alembic.ini`. Nếu fail → dựng từ scratch (`alembic init db/migrations`).

### ISSUE-009 — drnickv4 dùng LLM providers nào
- **Origin:** spec 02 §Assumptions #5
- **Severity:** medium (Ohana có thể cần bớt/thêm provider)
- **Status:** RESOLVED (phase 1.2 target-3, commit pending)
- **Action:** Đọc `providers/*.py` khi port module 1.2, log actual list. Nếu Ohana chỉ dùng subset → strip.
- **Resolution:** drnickv4 ships 2 providers — `openai_client` (chat + reasoning-mode) + `openai_embedder` (embeddings via OpenAI-compat gateway). Cả 2 port sạch, single OpenAI provider chain đủ MVP. Multi-provider (Anthropic/Together etc) defer.

### ISSUE-010 — agent/providers/ runtime-import blocked cho tới khi app/config + app/alert_service ported
- **Origin:** phase 1.2 target-3 (drnickv4 port)
- **Discovered:** 2026-07-16 · phase-1.2/target-3 session
- **Severity:** low (Phase 1.2 test bằng py_compile, không runtime-import; roadmap Phase 3+)
- **Status:** DEFERRED (Phase 3+ hoặc khi cần import providers runtime)
- **Detail:** `agent/providers/openai_client.py` imports `from app import alert_service` + `from app.config import get_settings`. `agent/providers/openai_embedder.py` imports `from app.config import get_settings`. Ohana chưa port `app/config.py` hoặc `app/alert_service.py` (spec 02 §3 IN scope = agent/embedder/providers/retrieval/parsing/storage; app/ mở rộng defer). test_ports dùng `py_compile` (parse-only, không runtime resolve) nên GATE_MODULE + GATE_FULL cả 2 pass. Rắc rối chỉ xuất hiện khi thực tế `from agent.providers.openai_client import OpenAIClient` được gọi — sẽ ImportError.
- **Action Phase 3+:** port `app/config.py` (pydantic-settings BaseSettings với env keys `openai_api_key`, `openai_model`, `openai_embed_model`, `reasoning_models`), port `app/alert_service.py` (fire-and-forget 429 counter — có thể stub thành no-op ở MVP).

### ISSUE-011 — DrNick milestone/spec lore residue in ported agent/ files (audit gap)
- **Origin:** spec 01 Phase 1 close audit (2026-07-16)
- **Discovered:** 2026-07-16 · while running ruff pre-check for Phase 1 GATE_FULL
- **Severity:** low (comments only — no functional/security impact, DoD §2 grep still passes)
- **Status:** DEFERRED (Phase 2+ agent/ touch or dedicated cleanup pass)
- **Detail:** Phase 1.2 target-1/target-3 audit used grep pattern `Spec [0-9]+|R[0-9]+\.[0-9]+|R-NEW-[0-9]+|debt [A-Z]|DrNick|Charlie|DEC-00[0-9]`. This missed:
  * DrNick milestone refs: `M1`..`M7`, `M1–M3 path` (progressive milestone naming)
  * DrNick feature refs: `FR2`, `FR4` (functional requirement IDs)
  * Provider chatter: `V4-Pro`, `DeepSeek`, `Together`, `DeepInfra`, `LiteLLM`
  * Comment-form spec refs missed by initial pass (e.g. `agent/providers/openai_client.py:28` import-line comment `# spec 34 P2`)
- **Files affected:** `agent/llm_client.py` (~15 hits), `agent/providers/openai_client.py` (~10 hits)
- **Why not blocking:** These are code comments about DrNick's evolution history. They don't reference ONFA/wallet/money (DoD §2 pattern clean). Ruff/mypy/pytest all pass. Test regex `onfa|wallet|pending_action|ConfirmEvent|2fa|balance|commission|transaction|deposit|withdraw` doesn't match either.
- **Action Phase 2+:** When Phase 2 touches agent/ area (unlikely per ALLOWED_FILES), OR run a dedicated cleanup sub-task with broader grep pattern `\bFR[0-9]+\b|\bM[0-9]+\b|V[0-9]-Pro|DeepSeek|Together|DeepInfra|LiteLLM|spec [0-9]+` — target rewrite comments to Ohana-generic. Est. 30min.

---

## Deferred bugs (chưa có — Phase 1 chưa chạy)

_Empty. Log ở đây khi port drnickv4 phát hiện bug nhưng defer fix per spec 02 §12 anti-pattern "KHÔNG fix bug drnickv4 trong lúc port"._

---

## Open — GĐ0.5 UI (spec 04)

### ISSUE-012 — React screens 0% test coverage; P1 GATE không khoá được deliverable của P1
- **Origin:** spec 04 §7 phase P1 · Wyatt accept tại ANCHOR 2026-07-17
- **Discovered:** 2026-07-17 · session spec-04-P1 (reviewer NEEDS_REVIEW finding #1 + #4)
- **Severity:** medium
- **Status:** DEFERRED (spec riêng — FE test harness)
- **Detail:** `tests/test_inbox_ui_e2e.py` (4 test) chỉ khoá HTTP contract mà screens bind vào — KHÔNG exercise dòng nào trong `web/src/**`. Xoá sạch `web/src/screens/*.tsx` thì GATE `pytest tests/test_inbox_ui_e2e.py -x -q` vẫn xanh. Kèm theo: 3/4 test GREEN ngay từ đầu, không RED được, vì brief P0 bảo mount `api/inbox.py` trong khi spec §7 P1 step 2 giao việc mount cho P1 → contract đã live trước khi P1 viết dòng React nào. TDD discipline không thoả ở P1.
- **Why not blocking:** DoD §2.5 chỉ yêu cầu backend flow `draft → approve → status flip` (đã đạt, 42/42 test xanh). GĐ0.5 = local demo Wyatt/Tân, chưa có seller thật. Thêm harness = dep mới (`vitest`/`playwright`) + config mới → phase riêng đúng nghĩa, không nhét vào P1.
- **Action:** (1) Wyatt/Tân smoke browser thủ công theo spec 04 §10 PC6 TRƯỚC khi merge `feat/gd0_5-inbox-ui` — session P1 không có browser harness nên KHÔNG verify được rendering/click-through/polling/`document.cookie` parsing. (2) Mở spec riêng cho FE test harness: Vitest+RTL (nhẹ, test component) hoặc Playwright (nặng, test click-through thật) — quyết lúc scope. Ưu tiên trước khi có seller thật (spec 05 real login).

### ISSUE-016 — Embedder THẬT là dead code: `app/config.py` chưa bao giờ tồn tại → F1 wiki-RAG chưa từng chạy với embedding thật
- **Origin:** phát hiện lúc executor P2 wire `api/admin.py` mount (spec 04) 2026-07-17
- **Discovered:** 2026-07-17 · session spec-04-P2
- **Severity:** **high** (không chặn GĐ0.5 vì PRE-003 chưa land, nhưng chặn F1 thật)
- **Status:** OPEN — chờ quyết định build `app/config.py`
- **Detail:** `agent/providers/openai_embedder.py::OpenAIEmbedder.__init__` gọi vô điều kiện `app.config.get_settings()`. **`app/config.py` không tồn tại trên disk VÀ không có trong git history** (verify: `git log --all -- app/config.py` rỗng). `OpenAIEmbedder()` → `ModuleNotFoundError: No module named 'app.config'`. Cùng vấn đề với `agent/providers/openai_client.py`. Đây là dead code port từ drnickv4, chưa bao giờ wire vào `app/main.py` — liên quan ISSUE-010 nhưng rộng hơn: không chỉ "runtime-import blocked", mà là **không có embedder chạy được nào trong repo**.
- **Hệ quả:** spec 01 Phase 3 tick F1 wiki-RAG DONE với gate `test_wiki_rag.py` 2/2 — nhưng gate đó dùng `FakeEmbedder` inline. Nghĩa là **F1 chưa từng chạy với embedding thật một lần nào**. P2 mount `api/admin.py` phải dùng `_DeterministicDevEmbedder` (hash-based) làm live default vì không có lựa chọn khác.
- **Đã mitigate (P2):** `_DeterministicDevEmbedder.embed()` raise `RuntimeError` nếu `OHANA_ENV != "dev"` + test `test_dev_embedder_refuses_to_run_outside_dev`. Không gate thì ingest sẽ trả `{"success": true, "chunks": N}` với vector rác → `search_wiki` trả chunk gần-ngẫu-nhiên → AI trả lời khách sai mà không ai thấy stack trace (silent-wrong, tệ hơn crash — vi phạm priority #1 "safety → user trust"). Gate đặt ở `embed()` chứ không ở `default_embedder()` để `app/main.py` vẫn import được (màn P0/P1 không chết theo).
- **Action:** (1) Quyết build `app/config.py` (Settings: `OPENAI_API_KEY`, embed model/dim, `OHANA_JWT_SECRET`, `DATABASE_URL`) — hiện 3 chỗ tự đọc env riêng lẻ (`db/session.py`, `auth/identity.py`, `bridge/ohana_client.py`) đều ghi chú "no app.config coupling until Phase 3+". (2) Wire `OpenAIEmbedder` thật vào `default_embedder()`, xoá `_DeterministicDevEmbedder`. (3) Re-verify F1 end-to-end với embedding thật + wiki thật (PRE-003). **Phải xong TRƯỚC khi tuyên bố F1 dùng được cho khách thật.**

### ISSUE-015 — Ngưỡng `min 100 chars` cho wiki ingest là phỏng đoán, chưa có dữ liệu
- **Origin:** spec 04 §3 C · reviewer P2 flag backend `min_length=1` lệch spec
- **Discovered:** 2026-07-17 · session spec-04-P2
- **Severity:** low
- **Status:** OPEN — revisit khi PRE-003 land
- **Detail:** Spec ghi textarea "min 100 chars". Wyatt/main session chốt đó là **gợi ý UX client-side**, backend giữ `min_length=1`. Lý do: caller là admin đã xác thực (vốn ingest được nội dung tuỳ ý ≥100 ký tự) → ép 100 server-side không chặn rác, chỉ chặn rác ngắn, đổi lại từ chối fact hợp lệ ngắn (`"Freeship đơn từ 400k."` = 21 ký tự).
- **Action:** Khi PRE-003 land wiki thật, đo độ dài doc điển hình → quyết có cần ngưỡng server-side không, và nếu có thì bao nhiêu. Nếu vẫn không cần → xoá `MIN_TEXT_LENGTH` client cho khỏi gây nhầm.

### ISSUE-014 — Test suite không có cleanup tập trung; row rò rỉ khi test crash giữa chừng
- **Origin:** phát hiện lúc smoke browser P1 (Wyatt xác nhận 3 màn chạy) 2026-07-17
- **Discovered:** 2026-07-17 · session spec-04-P1 · tìm thấy 1 row mồ côi `shop_id='shop_a', status='pending', draft="I'm not sure."` trong `pending_reply` trước khi chạy suite
- **Severity:** low
- **Status:** OPEN
- **Detail:** Không có `tests/conftest.py`, không có autouse cleanup. Chỉ `tests/test_inbox_ui_e2e.py` có teardown fixture (`seeded_replies`, executor P1 tự thêm sau khi tự bắt được bug). Các file dùng `shop_a`/`shop_b` (`test_orchestrator.py`, `test_policy_gate.py`, `test_tenant_isolation.py`, `test_ohana_tools.py`, `test_wiki_rag.py`) không dọn. Suite chạy trọn vẹn thì rows về 0, nhưng test crash/interrupt giữa chừng sẽ để lại row.
- **Why not blocking:** Suite hiện xanh 42/42, rows=0 sau full run. Row rò rỉ **không làm vỡ test nào** vì tenant isolation che: inbox của `fixture-shop-001` không bao giờ thấy row `shop_a`. ⚠️ Chính điều này là rủi ro thật — feature (tenant scope) đang che giấu test pollution, nên lỗi chỉ lộ khi 2 test tình cờ dùng chung `shop_id` (đúng cái đã xảy ra ở P1 với `fixture-shop-001`).
- **Action:** Thêm `tests/conftest.py` với autouse fixture truncate `pending_reply` (+ các bảng test khác) giữa các test, hoặc transaction-rollback pattern. Gộp vào spec FE test harness (ISSUE-012) hoặc làm riêng. Est. 30 phút.

### ISSUE-013 — `web/.oxlintrc.json` thiếu ignorePatterns cho `web/dist/`
- **Origin:** spec 04 phase P0 (config gap) · phát hiện lúc P1
- **Discovered:** 2026-07-17 · session spec-04-P1
- **Severity:** low
- **Status:** OPEN
- **Detail:** `pnpm lint` emit ~60 warning từ bundle minified trong `web/dist/`, không phải từ source. `npx oxlint src` trên code thật thì sạch (0 warning). Noise này làm lint output vô dụng — người đọc sẽ quen bỏ qua rồi miss warning thật.
- **Why not blocking:** GATE dùng pytest, không dùng oxlint. `web/.oxlintrc.json` ngoài ALLOWED_FILES của P1.
- **Action:** Thêm `"ignorePatterns": ["dist/**"]` vào `web/.oxlintrc.json`. Gộp vào P2 hoặc spec FE test harness (ISSUE-012). Est. 2 phút. Lưu ý: nếu sau này thêm CI Node build step thì `dist/` sẽ hết committed (xem deviation #3 của P0) → issue này tự biến mất.

---

## Waivers / trade-offs (chưa có)

_Empty. Log ở đây khi Wyatt approve `RISK_WAIVER` để hạ tier dưới floor, hoặc skip test/gate với rationale._

---

## Resolved (chưa có)

_Empty. Khi issue chuyển RESOLVED, di chuyển vào đây kèm commit SHA + resolved-in-phase._
