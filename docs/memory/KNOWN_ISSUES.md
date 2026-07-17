# KNOWN_ISSUES — Ohana AI Seller

> Nơi log deferred bugs / assumption breaks / waivers / open PRE checks. Update mỗi sub-phase (ghi mới, KHÔNG xoá cũ — chỉ đổi STATUS + gắn resolved commit SHA).
>
> Last updated: 2026-07-16 · Status: PRE-BOOTSTRAP (chưa có code, chưa Phase 1.0)

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

## Waivers / trade-offs (chưa có)

_Empty. Log ở đây khi Wyatt approve `RISK_WAIVER` để hạ tier dưới floor, hoặc skip test/gate với rationale._

---

## Resolved (chưa có)

_Empty. Khi issue chuyển RESOLVED, di chuyển vào đây kèm commit SHA + resolved-in-phase._
