# KNOWN_ISSUES — Ohana AI Seller

> Nơi log deferred bugs / assumption breaks / waivers / open PRE checks. Update mỗi sub-phase (ghi mới, KHÔNG xoá cũ — chỉ đổi STATUS + gắn resolved commit SHA).
>
> ⚠️ **Nguồn sự thật là dòng `Status:` của TỪNG entry, không phải header này.** Header viết tay, không sinh máy, đã rot ít nhất 2 lần (ISSUE-018 khai MỞ sau khi `be91ef9` đóng · ISSUE-019 khai MỞ sau khi WAIVER-001 đóng). Nếu header nói khác entry, tin entry. Dashboard trạng thái sống: `docs/roadmap-dashboard.html`.
>
> Trạng thái sprint (chốt 2026-07-24, có thể lag sau session gần nhất): xem `docs/ROADMAP-STATUS.md` (máy sinh) và `docs/memory/SESSION_LOG.md`. Không chép số vào đây.

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
- **Status:** ✅ ĐÓNG 2026-07-21 (spec 12 W0). Cả hai nửa xong: config (spec 05 P0) + alert_service (module 97b6d87 + wire spec 12 W0). 429 giờ ĐƯỢC đếm ở đường chat thật.
- **Cập nhật 2026-07-21 (spec 12 W0 — ĐÓNG):** `api/chat.py:get_llm_client()` tiêm `alert_service.record_provider_429` làm `on_rate_limit` (commit ffa8cf5, checkpoint DONE, EVIDENCE efb5f00, STATE_HASH eac894f447dc, REVIEW=APPROVE tier=medium). Import TRONG hàm ⇒ guard `test_openai_client_imports_without_alert_service` vẫn xanh. Test `tests/test_llm_429_wiring.py`: (a) client re-raise `RateLimitError` nguyên vẹn + count+1; (b) `get_llm_client` truyền đúng hook. **Caveat còn lại (KHÔNG thuộc ISSUE-010, spec riêng khi cần):** bộ đếm in-memory process-local (Redis chưa wire) · webhook-path 429 (webhook chưa mount, PRE-004) · alerting poller/reader chưa có.
- **Detail:** `agent/providers/openai_client.py` imports `from app import alert_service` (line 28) + `from app.config import get_settings` (line 13). `agent/providers/openai_embedder.py` imports chỉ `from app.config import get_settings`. test_ports dùng `py_compile` (parse-only) nên GATE pass dù runtime-import vỡ.
- **Cập nhật 2026-07-19 (spec 07 G0) — COUPLING GỠ, ISSUE VẪN OPEN:** `OpenAIClient` KHÔNG còn import module-level `app.alert_service`; telemetry 429 thành hook tiêm `on_rate_limit` (`Callable[[], Awaitable[None]] | None`). Module import sạch, `TogetherClient` dựng được trên nó. `xfail(strict=True)` trong `tests/test_config.py` đã **ĐẢO CHIỀU** thành assertion thật (`test_openai_client_imports_without_alert_service`) — giữ test để chặn ai đó thêm lại import module-level vào thứ chưa tồn tại.
  - ⚠️ **VẪN OPEN:** `app/alert_service.py` CHƯA port. Hôm nay **429 không được đếm ở đâu cả** trừ khi caller tự tiêm hook — đây là capability regression spec 07 chấp nhận có ý thức, KHÔNG phải đã giải quyết.
- **Cập nhật 2026-07-17 (spec 05 P0):** `app/config.py` đã build (Settings 4 field). Hệ quả: `OpenAIEmbedder` (F1) giờ import + instantiate được — nửa embedder của ISSUE-010 + toàn bộ ISSUE-016 config-half GIẢI QUYẾT. NHƯNG `OpenAIClient` (LLM chat, F2/F3) VẪN vỡ vì `app/alert_service.py` chưa port. Encode ở `tests/test_config.py::test_openai_client_import_blocked_by_unported_alert_service` (`xfail(strict=True)` — flip hard-fail khi port xong, không rot).
- **Action còn lại:** port `app/alert_service.py` (fire-and-forget 429 counter — stub no-op OK ở MVP) — thuộc **LLM-client wiring spec** (F2/F3, cùng lúc wire `OpenAIClient` + concrete `Drafter` + webhook mount, gated PRE-004). KHÔNG thuộc spec 05 (F1 không cần LLM client). Khi làm: xoá xfail ở test_config.py.
- **Cập nhật 2026-07-21 (AI-coder audit + port nửa an toàn):**
  - **Module ĐÃ land:** `app/alert_service.py` — `record_provider_429()` fire-and-forget, fail-OPEN
    (không raise, gọi từ except của client), + `provider_429_count()` reader. Bộ đếm **in-memory
    process-local** (Redis CHƯA wire trong ohana; drnick bản Redis kéo theo `health_service`+
    `latency_service`+poller = spec 34/36/40, ngoài scope). Chữ ký khớp hook `on_rate_limit` để
    tiêm thẳng. Test: `tests/test_alert_service.py` (4 ca — đếm, fail-open khi logging chết, chữ ký,
    canh import-clean). Đổi ruột sang Redis sau KHÔNG phải đổi chữ ký.
  - **Action "xoá xfail" = STALE:** xfail đã đảo chiều ở spec 07 G0 thành assertion thật
    `test_openai_client_imports_without_alert_service`; `openai_client.py:28` giờ là `get_settings`,
    không còn `from app import alert_service`. Không còn xfail nào để xoá.
  - **⚠️ VẪN OPEN — 429 vẫn CHƯA được đếm ở đường thật:** client chỉ dựng ở `api/chat.py:83`
    (`TogetherClient()`) mà KHÔNG tiêm `on_rate_limit`. Wire-in = sửa `api/chat.py` = **RISK_PATH ⇒
    cần ADP phase** (đề xuất RISK:medium — chạm RISK_PATH nhưng telemetry fail-open, không đổi hành
    vi gửi/tiền). Module này là ĐÍCH tiêm sẵn sàng; issue đóng khi phase đó wire + test đường 429 thật.

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

### ISSUE-019 — `ruff check .` ĐỎ trên `main`; nguyên nhân gốc là `ruff>=0.4` không pin
- **Origin:** phát hiện lúc chạy GATE_FULL của spec 08 E0 (không phải do E0 gây ra)
- **Discovered:** 2026-07-19 · session spec-08-E0
- **Severity:** medium (CI đỏ, không phải bug runtime)
- **Status:** ✅ RESOLVED — action 1+2+3 (2026-07-19, pin ruff) · action 4 ĐÓNG bằng WAIVER-001 / DEC-OHANA-04 (2026-07-20) · **action 6 XONG 2026-07-20: pin toàn bộ 16 runtime dep.** Đo trước khi pin: 4 đã qua đổi MAJOR — `openai` 1.30→2.45 (SDK của cả TogetherClient lẫn TogetherEmbedder), `pypdf` 4→6.14, `redis` 5→8.0, `sse-starlette` 2.1→3.4. Version pin = đúng thứ CI run 29709797545 chạy xanh đủ 11 step. Toàn bộ toolchain (4 dev + 16 runtime) giờ pin cứng.

- **🔴 BẰNG CHỨNG CI THẬT (2026-07-20, sau khi GitHub Actions hồi phục) — action 4 ĐÓNG, và kết quả tệ hơn ước lượng local:**

  Trước đây tôi chỉ suy luận từ `git stash` trên máy local ("19/22 phase DONE không tái lập được `ruff check`"). Giờ đã hỏi thẳng GitHub:

  ```
  23 run  = TOÀN BỘ lịch sử repo (cũ nhất 2026-07-17T15:53, b93b8ed "Merge GĐ0.5 Inbox UI")
  ✅  4 xanh — CẢ BỐN đều sau commit vá ruff 01c2479 (2026-07-19T15:36)
  ❌ 19 đỏ
  ```

  **CI CHƯA TỪNG XANH MỘT LẦN NÀO** cho tới `01c2479` hôm nay. Spec 04, 05, 06, 07 — mọi phase — đều được `adp-checkpoint.sh` stamp DONE trong lúc CI đỏ. Bao gồm `5fa5b04` (spec 07 G2 checkpoint evidence) và `50e4862` (meta-sync sau spec 06).

  **Lấy mẫu 2 run đỏ, cả hai chết ở CÙNG step:** `Ruff lint (incl S / bandit)` — run `29643425884` (50e4862, 18/07) và `29671576305` (5fa5b04, 19/07).

  ⚠️ **Chưa verify:** rule cụ thể của các run đỏ CŨ. S603 chỉ land cùng spec 07 (19/07), nên run đỏ từ 17–18/07 phải do rule khác. Log không lấy được (Actions API còn partial-outage lúc điều tra). **Đừng đọc thành "tất cả đều do S603"** — mới chỉ chứng minh được *cùng một step*, chưa phải *cùng một nguyên nhân*.

  **Ý nghĩa với ADP spine:** `GATE_FULL` chạy local với `.ruff_cache` nhiễm độc trả xanh, CI chạy sạch trả đỏ — và EVIDENCE stamp vào spec ghi lại cái xanh giả. Đây không phải "CI hơi lệch local"; đây là **spine đã ký DONE cho thứ chưa từng qua gate thật**. Việc pin + `--no-cache` vá nguyên nhân từ nay về sau, KHÔNG hồi tố các EVIDENCE cũ.

  **Action còn lại (chưa ai nhận):** quyết xem EVIDENCE của 22 phase DONE trước `01c2479` có cần re-stamp không, hay chấp nhận và ghi waiver. Đây là câu hỏi cho Wyatt, không phải việc máy quyết.
- **Detail:** `ruff check .` tại HEAD trả **1 error** — `S603` (`subprocess` call: check for execution of untrusted input) ở `tests/test_chat_endpoint.py:313`. Verify bằng `git stash -u` (cây sạch, không có thay đổi E0) ⇒ lỗi có sẵn, land cùng `3a41bfe` (spec 07). CI `.github/workflows/ci.yml:64` chạy đúng lệnh này ⇒ **CI đang đỏ ở bước ruff**.
  Bản thân S603 ở đây là **báo nhầm**: lệnh chạy là `[sys.executable, "-c", probe]` với `probe` là literal viết trong file test, không có input ngoài. Đó là subprocess CỐ Ý — probe đo thứ chỉ quan sát được ở tiến trình sạch (thứ tự `dictConfig` vs `import app.main`), in-process không đo được.
- **Nguyên nhân gốc — quan trọng hơn cái lỗi:** `pyproject.toml:27` khai `ruff>=0.4`, không pin. Local đang **0.15.22**. Một bản ruff mới bật thêm rule là CI đỏ mà **không ai đổi một dòng code nào**. Nghĩa là gate của repo phụ thuộc ngày cài đặt — chạy hôm nay xanh, chạy tuần sau đỏ. Hệ quả thứ hai: một phase từng checkpoint DONE với `GATE_FULL` chứa `ruff check .` giờ không tái lập được kết quả đó, tức EVIDENCE cũ mất tính kiểm chứng.
- **Why not blocking E0:** lỗi nằm ở `tests/test_chat_endpoint.py` — ngoài `ALLOWED_FILES` của E0 kể cả sau khi Wyatt mở rộng. Sửa kèm = scope drift đúng loại mà ADP dựng lên để chặn. **Nhưng nó CHẶN checkpoint E0**, vì `GATE_FULL` của E0 có `ruff check .` trong đó.
- **Action:** (1) ✅ Pin `ruff==0.15.22`. (2) ✅ Chặn S603 tại đúng dòng — KHÔNG tắt toàn repo. (3) ✅ Commit riêng. (4) ✅ Rà 22 phase DONE — kết quả ở AMENDMENT dưới. (5) ✅ `--no-cache` vào mọi bước ruff (ci.yml + CLAUDE.md §1 + GATE_FULL spec 08 E1/E2). (6) ✅ Pin `mypy==2.3.0` + `pytest==9.1.1` + `pytest-asyncio==1.4.0` — cả ba đã trôi qua major. (7) ⏳ **CÒN LẠI: runtime deps chưa pin.** Đo 2026-07-19: `openai` >=1.30 → **2.45.0** · `redis` >=5.0 → **8.0.1** · `pypdf` >=4.0 → **6.14.2** · `sse-starlette` >=2.1 → **3.4.5** (4/13 gói trôi qua major). Đáng lo nhất là `openai` — SDK mà `TogetherClient` + `TogetherEmbedder` dùng. Pin runtime KHÁC LOẠI với pin dev-tool: nó đổi thứ chạy trong production, cần test rồi mới ký, và đúng ra nên dùng **lockfile** chứ không phải `==` trong pyproject (`==` không khoá transitive dep). Cần Wyatt quyết cách làm trước khi ai đó động vào.

---

#### AMENDMENT 2026-07-19 — chẩn đoán ban đầu THIẾU. Nguyên nhân trực tiếp là CACHE, không phải version.

Pin version là đúng nhưng không đủ. Thứ thật sự làm gate nói dối:

```
ruff check .              →  All checks passed!     ← đúng lệnh GATE_FULL đang chạy
ruff check . --no-cache   →  Found 4 errors
```

Cùng source, cùng binary. Xoá `.ruff_cache` rồi chạy lại lệnh CŨ ⇒ FAIL 4, ổn định qua nhiều lần chạy. `.ruff_cache` do một bản ruff trước ghi ra **không bị vô hiệu khi ruff nâng cấp**.

4 lỗi thật (I001, import chưa sắp — đã `--fix`): `agent/providers/openai_embedder.py:4` · `tests/test_tenant_isolation.py:36,66,114`.

**Hệ quả phải ghi ra, không giấu:**
- **Checkpoint spec 08 E0 (`8ba4fef`) có một bước gate xanh giả.** `GATE_FULL: PASS` bao gồm `ruff check .`, mà bước đó đọc cache. Ba bước còn lại (pytest/mypy/format) hợp lệ. Đã re-verify sau khi vá — xem `docs/reviews/08-E0-gate-reverify.md`.
- Trong session phát hiện, "ruff sạch" bị báo sai **hai lần theo hai cơ chế khác nhau**: lần đầu do chạy **scoped** (`ruff check app/config.py` rồi khai như toàn repo — đúng hình dạng ISSUE-018), lần sau do **cache** dù đã chạy đúng lệnh. Bài học: chạy đúng lệnh vẫn chưa đủ để lời khai thành bằng chứng.
- **CI đáng lẽ đã đỏ.** Runner không restore `.ruff_cache` (chỉ cache pip) ⇒ CI thấy 4 lỗi này. Chưa ai xác nhận trạng thái Actions — **cần kiểm tab Actions**, đây là suy luận từ config, không phải quan sát.

**Rà 22 phase DONE dưới ruff pin + `--no-cache`** (bung tree bằng `git archive <sha>`, chạy ruff lên source lúc phase đó ký DONE):

| Kết quả | Số phase |
|---|---|
| `ruff check` PASS | **3/22** — `02:1.0`, `02:1.1`, `01:phase-1` |
| `ruff check` FAIL | **19/22** (3–5 lỗi, tăng dần theo thời gian) |
| `ruff format` FAIL | 7/22 |

Đọc cho đúng: **19 phase đó KHÔNG làm sai.** Chúng pass gate hợp lệ dưới ruff đương thời. Bảng này trả lời đúng một câu — *"EVIDENCE cũ có tái lập được dưới ruff hôm nay không"* — và câu trả lời là không, với 19/22. Đó là chi phí của `>=` không pin, lần đầu đo được bằng số.

**KHÔNG sửa 19 phase cũ.** Chúng DONE hợp lệ theo tiêu chuẩn lúc đó; viết lại lịch sử không mua được gì. Giá trị nằm ở chỗ từ nay gate không tự lừa nữa.
- **Ghi chú cho lần sau:** lỗi lộ ra vì `GATE_FULL` chạy `ruff check .` (toàn repo). Trong session này tôi từng báo "ruff sạch" sau khi chỉ chạy `ruff check app/config.py` — scoped. Gate scoped trả lời câu hỏi hẹp hơn câu mình đang khẳng định; đó chính là hình dạng của ISSUE-018. Khi báo trạng thái gate, chạy đúng lệnh mà gate khai.

### ISSUE-017 — ✅ RESOLVED 2026-07-20 (spec 09 C0) — unique constraint + upsert đối xứng

- **Đóng bằng gì:** `uq_conversations_shop_cus_chan_thread` UNIQUE **NULLS NOT DISTINCT** trên `(shop_id, customer_id, channel, external_thread_id)` (migration `0005`) + `resolve_conversation()` đổi sang `on_conflict_do_nothing` + re-select, đối xứng với nhánh `Customer`. Bằng chứng: `docs/smokes/09-C0.md`.
- **Chọn hình dạng B, Wyatt ký:** thêm `external_thread_id` vào khoá thay vì `(shop,cus,chan)` như đề xuất gốc của issue. Lý do: câu "Zalo có xoay `thread_id` giữa cùng một mạch không?" nằm trong PRE-004 đang BLOCKED; khi phải đoán thì chọn cái **đoán sai còn sửa được** — B sai ⇒ phân mảnh, gộp lại được; A sai ⇒ gộp nhầm hai mạch, không tách lại được. Hôm nay B hành xử y hệt A vì `thread_id` luôn NULL.
- **`NULLS NOT DISTINCT` là phần bắt buộc, không phải trang trí:** mặc định SQL coi NULL là distinct ⇒ UNIQUE thường sẽ cho qua hai row `(shop,cus,chan,NULL)`, mà đó là ca phổ biến nhất hôm nay. Thiếu cờ ⇒ constraint trông như đã vá mà không vá gì.
- **Bài học khi viết test:** bản đầu tái hiện race bằng `asyncio.gather` và **XANH TRƯỚC KHI CÓ CONSTRAINT** — hai transaction không đan xen. Đã thay bằng test tất định viết thẳng thứ tự SELECT-A → SELECT-B → INSERT-A → INSERT-B. Test `gather` giữ lại nhưng hạ vai trò, docstring ghi rõ KHÔNG được đọc như bằng chứng race.
- **CÒN LẠI:** nếu `window_status` hết hạn phải mở conversation MỚI thì constraint này sẽ chặn — chưa ai định nghĩa. Phải trả lời trước khi làm `GD0-WINDOW`. Và khi PRE-004 về, rà lại lựa chọn B.

<details><summary>Mô tả gốc (giữ nguyên)</summary>

### ISSUE-017 (gốc) — `channels/identity.py`: thiếu unique constraint → race có thể tạo 2 Conversation cho 1 khách
- **Origin:** spec 06 F1 (khai KNOWN UNCOVERED ngay trong code + review artifact `docs/reviews/06-F1-auto-verdict.json`)
- **Discovered:** 2026-07-18 · session spec-06-F1
- **Severity:** medium (chưa chạm được, nhưng chạm được ngay khi webhook mount)
- **Status:** OPEN
- **Detail:** `resolve_conversation()` upsert `Customer` bằng `ON CONFLICT DO NOTHING` trên `uq_customers_shop_chan_ext` (race-safe), NHƯNG phần `Conversation` là **select-then-insert** và bảng `conversations` KHÔNG có unique trên `(shop_id, customer_id, channel)`. Hai tin nhắn đến đồng thời từ cùng một khách → 2 Conversation.
- **Why not blocking now:** `api/webhook.py` **chưa mount** trong `app/main.py` (thiếu concrete `Drafter`), nên không luồng nào gọi hàm này đồng thời. Đây là lỗi TIỀM ẨN, không phải đang chảy máu.
- **Action:** Thêm Alembic migration `UNIQUE (shop_id, customer_id, channel)` trên `conversations` + đổi phần Conversation sang cùng shape upsert như Customer. **BẮT BUỘC làm TRƯỚC khi Spec 03c mount webhook** — đừng dựa vào "chưa xảy ra bao giờ".

</details>

### ISSUE-018 — `_blank_env_means_unset` KHÔNG phủ complex field; docstring khai "áp cho MỌI field" là SAI
- **Origin:** spec 07 G0 (`app/config.py`) — phát hiện khi so sánh 2 bản CLAUDE.md, 2026-07-19
- **Discovered:** 2026-07-19 · session claude-md-merge
- **Severity:** medium (không chảy máu prod hôm nay; là lỗ trong chính hàng rào dựng lên để chặn lớp bug này)
- **Status:** ✅ RESOLVED 2026-07-21 (`be91ef9` fix + `4531805` docstring). `reasoning_models: Annotated[frozenset[str], NoDecode]` + `_parse_reasoning_models` validator (`app/config.py:146-151`) — `NoDecode` tắt JSON-parse tầng `EnvSettingsSource`, chuỗi thô lọt tới `_blank_env_means_unset`, rỗng ⇒ frozenset(). Field phức thứ hai xuất hiện ⇒ lặp lại đúng cặp `NoDecode` + validator, KHÔNG trông vào `_blank_env_means_unset` một mình.
- **Detail:** `_blank_env_means_unset` là `@model_validator(mode="before")`, lọc `""` khỏi dict input. Nhưng với field kiểu phức (`reasoning_models: frozenset[str]`), pydantic-settings `EnvSettingsSource` **parse JSON TRƯỚC** khi validator chạy ⇒ chuỗi rỗng nổ ngay tại tầng source, validator không bao giờ thấy. Kiểm thật:
  ```
  REASONING_MODELS= → SettingsError: error parsing value for field "reasoning_models"
                      from source "EnvSettingsSource"
  ```
  Nghĩa là hàng rào chỉ bảo vệ field vô hướng (`str`, `str | None`). Docstring hiện khai *"Áp cho MỌI field, không riêng Together"* — sai, và câu sai đó đã được chép nguyên vào CLAUDE.md, tức nó đang **nhân bản**. Đây đúng kịch bản `.env.example` mà spec 07 dựng hàng rào để chặn: admin copy template, để trống dòng chưa dùng → app không chạy, thông báo lỗi không nói gì về "để trống".
- **Why not blocking:** `reasoning_models` là field phức DUY NHẤT hiện tại, và `.env.example` không liệt kê `REASONING_MODELS`. Lỗi là fail-loud (raise lúc khởi động), không phải silent-wrong.
- **Action:** (1) Sửa docstring cho đúng phạm vi — ưu tiên cao hơn sửa code, vì docstring sai đang được chép đi. (2) Cân nhắc `settings_customise_sources` hoặc `NoDecode` + validator riêng để chuẩn hoá rỗng trước khi source parse. (3) Thêm test `REASONING_MODELS=` rỗng khoá hành vi đã chọn (dù chọn "raise" hay "coi như unset" — hiện KHÔNG có test nào chạm ca này).

### ISSUE-016 — ✅ RESOLVED 2026-07-19 (spec 08 E2) — F1 wiki-RAG chạy THẬT trên Together e5

- **Đóng bằng gì:** `tests/test_wiki_rag_live.py -m live` PASS **4/4** với key thật, e5 thật,
  Postgres thật. Bằng chứng: `docs/smokes/08-E2.md`. Ba spec-phase đưa nó tới đây — 08 E0
  (`TogetherEmbedder` + tách query/passage), E1 (migration `Vector(1536)`→`Vector(1024)` +
  wire factory), E2 (live acceptance).
- **Định nghĩa "đóng" mà tôi dùng, nói rõ để không ai đọc rộng hơn:** live test chứng minh
  **thứ hạng** — hỏi về phí ship thì đoạn phí ship xếp ĐẦU, 3/3 truy vấn xoay vòng, mỗi câu
  kéo một chunk khác lên. Bản test cũ chỉ assert `any(...)` trên cả danh sách, tức chunk đúng
  nằm CUỐI dưới ba đoạn lạc đề vẫn xanh — đó không phải điều F1 hứa với seller.
- **CÁI NÀY VẪN CHƯA CHỨNG MINH:** corpus dùng để đo là **văn bản mẫu 3 đoạn do tôi viết**,
  không phải corpus thật của seller (PRE-003 chưa land). Retrieval tốt trên 3 chunk tách bạch
  chủ đề là bài dễ. Khi corpus thật land — hàng trăm chunk, chủ đề chồng lấn, văn phong seller
  thật — phải đo LẠI. ISSUE-016 đóng đúng phạm vi "đường ống chạy được với embedding thật",
  KHÔNG phải "chất lượng retrieval đã nghiệm thu ở quy mô thật".
- **Nợ kèm theo:** chưa có index vector (ivfflat/hnsw). Với 3 row thì seq-scan đúng; với corpus
  thật thì thiếu index sẽ thành vấn đề hiệu năng. Chưa ai nhận.

<details><summary>Lịch sử (giữ nguyên, không xoá)</summary>


- **Cập nhật 2026-07-19 — ADR PRE-007 đã ACCEPTED, blocker đổi từ 'chờ ký' sang 'chờ làm':** provider + embedding giờ là quyết định chốt (Together, `intfloat/multilingual-e5-large-instruct` 1024-dim). Việc còn lại KHÔNG còn là chờ ai duyệt mà là công việc thật: (1) `TogetherEmbedder` thay `OpenAIEmbedder`; (2) Alembic migration `Vector(1536)` → `Vector(1024)` (`db/models.py:_EMBED_DIM`); (3) re-embed corpus khi PRE-003 land; (4) chạy live acceptance **trên e5, KHÔNG phải OpenAI** — kết quả cũ trên OpenAI không áp dụng. Chưa có spec/phase nào nhận 4 việc này.
- **Origin:** phát hiện lúc executor P2 wire `api/admin.py` mount (spec 04) 2026-07-17
- **Discovered:** 2026-07-17 · session spec-04-P2
- **Severity:** **high** (không chặn GĐ0.5 vì PRE-003 chưa land, nhưng chặn F1 thật)
- **Status:** ⏳ CODE-COMPLETE (spec 05 P0+P1+P2, 2026-07-18) — **live acceptance CHƯA chạy → vẫn OPEN**. Đóng khi DoD #5 PASS.
- **Detail:** `agent/providers/openai_embedder.py::OpenAIEmbedder.__init__` gọi vô điều kiện `app.config.get_settings()`. `app/config.py` không tồn tại (git history rỗng). `OpenAIEmbedder()` → `ModuleNotFoundError`. Dead code port từ drnickv4.
- **Hệ quả:** spec 01 Phase 3 tick F1 DONE với gate `test_wiki_rag.py` 2/2 — nhưng gate đó dùng `FakeEmbedder` inline. **F1 chưa từng chạy với embedding thật một lần nào.**
- **Cập nhật 2026-07-18 (spec 05 — GIẢI QUYẾT nửa CODE):**
  - P0: `app/config.py` Settings landed → `OpenAIEmbedder` hết ModuleNotFoundError.
  - P1: `default_embedder()` env-selecting → có `OPENAI_API_KEY` thì dùng `OpenAIEmbedder` thật (`_DeterministicDevEmbedder` giữ lại cho dev-no-key, raise-outside-dev nguyên). `tests/test_wiki_rag_live.py` (`@pytest.mark.live`) soạn sẵn = DoD #5.
  - P2: env-reading gom qua `Settings()` fresh.
  - **CÒN LẠI (lý do vẫn OPEN):** `tests/test_wiki_rag_live.py -m live` CHƯA chạy với real `OPENAI_API_KEY` — không ai chứng minh F1 trả chunk đúng với embedding thật. Cả spec 05 thiết kế để checkpoint KHÔNG tự-tuyên-bố cái này (tránh lặp lại chính bẫy ISSUE-016).
- **Action còn lại:** Wyatt/Tân chạy `OPENAI_API_KEY=sk-... DATABASE_URL=<pg> .venv/bin/python -m pytest tests/test_wiki_rag_live.py -m live -x -q` → PASS → log vào SESSION_LOG → chuyển ISSUE-016 RESOLVED + xoá cảnh báo F1 trong CLAUDE.md. **Phải xong TRƯỚC khi tuyên bố F1 dùng được cho khách thật.** (PRE-003 wiki thật là bước content riêng, không chặn live acceptance — verify được với sample doc.)

</details>

### ISSUE-015 — Ngưỡng `min 100 chars` cho wiki ingest là phỏng đoán, chưa có dữ liệu
- **Origin:** spec 04 §3 C · reviewer P2 flag backend `min_length=1` lệch spec
- **Discovered:** 2026-07-17 · session spec-04-P2
- **Severity:** low
- **Status:** OPEN — revisit khi PRE-003 land
- **Detail:** Spec ghi textarea "min 100 chars". Wyatt/main session chốt đó là **gợi ý UX client-side**, backend giữ `min_length=1`. Lý do: caller là admin đã xác thực (vốn ingest được nội dung tuỳ ý ≥100 ký tự) → ép 100 server-side không chặn rác, chỉ chặn rác ngắn, đổi lại từ chối fact hợp lệ ngắn (`"Freeship đơn từ 400k."` = 21 ký tự).
- **Action:** Khi PRE-003 land wiki thật, đo độ dài doc điển hình → quyết có cần ngưỡng server-side không, và nếu có thì bao nhiêu. Nếu vẫn không cần → xoá `MIN_TEXT_LENGTH` client cho khỏi gây nhầm.

### ISSUE-014 — ✅ RESOLVED (spec 06 F2, commit 95ad405) — Test suite không có cleanup tập trung
- **Origin:** phát hiện lúc smoke browser P1 (Wyatt xác nhận 3 màn chạy) 2026-07-17
- **Discovered:** 2026-07-17 · session spec-04-P1 · tìm thấy 1 row mồ côi `shop_id='shop_a', status='pending', draft="I'm not sure."` trong `pending_reply` trước khi chạy suite
- **Severity:** low
- **Status:** ✅ **RESOLVED 2026-07-18** — `tests/conftest.py` đã land (spec 06 F2). Fixture `fresh_db` drop+create schema mỗi lần gọi, và **dispose engine trong teardown kể cả khi test raise** (trước đây `await engine.dispose()` cuối mỗi test bị bỏ qua hoàn toàn khi assert fail giữa chừng → rò pool mỗi lần fail). Test DB mới dùng fixture; test cũ **cố ý KHÔNG mass-refactor** (đổi test đang xanh chỉ để cho đẹp = rủi ro không được trả công) — chúng migrate dần khi có lý do khác để đụng vào.
- **Detail (lịch sử):** Không có `tests/conftest.py`, không có autouse cleanup. Chỉ `tests/test_inbox_ui_e2e.py` có teardown fixture (`seeded_replies`, executor P1 tự thêm sau khi tự bắt được bug). Các file dùng `shop_a`/`shop_b` (`test_orchestrator.py`, `test_policy_gate.py`, `test_tenant_isolation.py`, `test_ohana_tools.py`, `test_wiki_rag.py`) không dọn. Suite chạy trọn vẹn thì rows về 0, nhưng test crash/interrupt giữa chừng sẽ để lại row.
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

### ISSUE-020 — `last_inbound_at` / `window_status` chưa từng được GHI ⇒ scheduler 48h sẽ luôn trả rỗng
- **Origin:** spec 09 C0 follow-up — audit câu hỏi mở "window_status hết hạn có mở conversation MỚI không"
- **Discovered:** 2026-07-20
- **Severity:** medium (chưa chạm được — Phase 10 BLOCKED; nhưng sẽ hỏng ÂM THẦM ngay khi build)
- **Status:** OPEN
- **Detail:** `conversations.last_inbound_at` và `conversations.window_status` tồn tại trong `db/models.py` + migration `0003`, có cả index `idx_conv_shop_last_inbound`, nhưng **KHÔNG dòng code nào ghi vào chúng**. Verify bằng grep toàn repo (loại trừ khai báo cột): 0 hit.
  Spec 03 Phase 10 dự định query `conversations WHERE last_inbound_at + 48h - T`. Với `last_inbound_at IS NULL` ở mọi row, query trả **rỗng** ⇒ scheduler chạy đều, log sạch, seller KHÔNG BAO GIỜ được cảnh báo, và **không có exception nào**. Index cũng là index chết.
- **Cùng họ với ISSUE-017:** một cột được luồng qua schema nhưng không luồng qua code. Khác ở chỗ ISSUE-017 hỏng khi có tải, cái này hỏng ngay từ dòng đầu tiên.
- **Action:** `resolve_conversation()` là nơi tự nhiên để đóng dấu — nó chạy trên MỌI tin nhắn vào. Stamp `last_inbound_at=now()` và reset `window_status='active'` mỗi lần inbound. **Làm TRƯỚC khi build Phase 10**, đừng để scheduler dựng trên cột chết.
- **Ghi chú:** việc này KHÔNG chặn `GD0-WINDOW` về mặt thiết kế (ngữ nghĩa đã rõ, xem dưới), chỉ chặn nó hoạt động đúng.

---

### ISSUE-021 — L1 gỡ `shipping_info` khỏi `GD0-TOOLS` nhưng spec 03 Phase 4 vẫn frozen ở "3 read-tool"
- **Origin:** audit kickoff persona (2026-07-20) — 4 patch L1 `docs/ROADMAP.md`
- **Discovered:** 2026-07-20
- **Severity:** low (chưa chạm được — spec 03 Phase 4 BLOCKED chờ PRE-002; hỏng khi unblock)
- **Status:** OPEN
- **Detail:** Theo D7 (phân tầng theo HÌNH DẠNG DỮ LIỆU), intent 4/5/6 chuyển sang `lookup_size`/`lookup_shipping` đọc JSONB trên `shop_profile` ⇒ `shipping_info` không còn intent GĐ0 nào dùng. `docs/ROADMAP.md` §4.1 đã gỡ, `GD0-TOOLS` còn 2 tool (`product_info`, `account_lookup`).
  Nhưng `docs/tasks/03-Task-GD0-AcceptanceBackfill.md` **frozen** vẫn khai 3 tool ở 5 chỗ, gồm Phase 4 block: `GOAL: 3 read-tool mới trong registry: shipping_info(order_id), product_info(...), account_lookup(...)`.
  ⇒ Khi PRE-002 unblock, executor đọc spec (L2) sẽ build đúng cái L1 vừa bỏ. Không có gate nào bắt được: spec frozen là nguồn thật của executor, và L1 nằm NGOÀI vùng diff-bound có chủ ý (§5 CLAUDE.md).
- **Cố ý KHÔNG sửa:** `tools/ohana_read.py:13` docstring và `docs/memory/SHIPPED-SURFACE.md:96` mô tả **danh sách endpoint PRE-002 của Tân** — danh sách đó không đổi chỉ vì ta thôi dùng một cái. `docs/tasks/01-*.md` (DONE) và `docs/archive/*` là lịch sử, giữ nguyên.
- **Action:** khi PRE-002 unblock — TRƯỚC khi chạy spec 03 Phase 4, đối chiếu L1 §4.1 với Phase 4 block; hoặc sửa spec xuống 2 tool (cần Wyatt duyệt tường minh — sửa spec frozen ngoài `adp-checkpoint.sh`), hoặc phục hồi `shipping_info` vào L1 nếu API Tân có thứ `lookup_shipping` không thay được.

---

### ISSUE-022 — Cap 2000 ký tự cho persona là con số ĐẶT TẠM, chưa đo
- **Origin:** audit kickoff persona (2026-07-20) — §4.2 brief để mở "ngân sách token persona"
- **Discovered:** 2026-07-20
- **Severity:** low
- **Status:** OPEN (chờ đo)
- **Detail:** `GD0-SHOPS` acceptance vừa chốt `persona ≤ 2000 ký tự (≈600 token)`. Con số này **suy ra từ ước lượng, không từ đo đạc**: prompt hôm nay ~134 token (`api/chat.py`), tỉ lệ ký tự→token tiếng Việt lấy xấp xỉ 3.3. Chưa ai đo token thật của tiếng Việt có dấu trên tokenizer Llama-3.3, và chưa ai đo persona thật dài bao nhiêu vì **chưa có shop nào**.
  Đặt số để có ràng buộc cứng ngay từ migration đầu (nới cột sau rẻ, siết lại sau khi UI đã bind thì đắt) — không phải vì tin nó đúng.
- **Cùng họ với ISSUE-015** (ngưỡng `min 100 chars` wiki ingest cũng là phỏng đoán chưa có dữ liệu).
- **Action:** khi có ≥3 shop pilot viết persona thật — đo (a) độ dài thực tế, (b) token thật qua tokenizer, (c) `token_cached` mà `api/chat.py` đang log. Rồi chốt số chính thức hoặc bỏ cap nếu thực tế không ai chạm ngưỡng. Cho tới lúc đó **đừng trích 2000 như một quyết định đã ký**.
- **Chia hai câu hỏi (audit 2026-07-21, cùng khung ISSUE-023):**
  - **Q1 — token cost của cap 2000 ký tự?** Chia chung tỉ lệ ký tự→token với ISSUE-023 (thuộc tính
    tokenizer+ngôn ngữ, gần như độc lập độ dài) ⇒ **KHÔNG cần call live mới**. Với **3.55 ký tự/token
    đo thật** (xem ISSUE-023 Q1): persona 2000 ký tự ≈ **563 token** (giấy tờ `≈600` — nhất quán, hơi
    thấp hơn). Cap persona KHÔNG làm vỡ ngân sách; số `≈600` của issue này *tự nhất quán* với 3.3
    (2000/3.3 = 606), KHÁC ca 1800 bị gán nhầm ở ISSUE-023.
  - **Q2 — độ dài persona thật + có ai chạm 2000 không?** HARD-BLOCKED: cần ≥3 shop pilot, hiện 0
    shop. Không bịa. ISSUE-022 CHỈ đóng khi có Q2.
  - Caveat 3.55 (đo trên text lặp, có thể lạc quan) áp cho cả đây — xem ISSUE-023 Q1.

## Waivers / trade-offs

### WAIVER-001 — EVIDENCE của 22 phase DONE trước khi CI xanh lần đầu
- **Ký:** Wyatt · 2026-07-20 · toàn văn: `docs/decisions/DEC-OHANA-04-evidence-waiver-pre-ci-green.md`
- **Gốc:** ISSUE-019. CI chưa từng xanh cho tới `01c2479` (4 xanh / 19 đỏ / 23 run = toàn bộ lịch sử repo).
- **Waive:** không re-stamp EVIDENCE của 22 phase DONE trước `01c2479`.
- **KHÔNG waive:** (1) tính đúng của code hiện tại — HEAD `aae835c` qua **đủ 11 step CI** gồm alembic + pytest trên container sạch; (2) quy tắc `--no-cache` + pin từ nay; (3) nghĩa vụ nói thật.
- **Cách đọc "DONE" cho phase trước `01c2479`:** = *"gate local pass, CI chưa từng xác nhận"*, KHÔNG phải *"đã qua gate thật"*. Ai trích số liệu giai đoạn đó phải kèm câu này.
- **Phạm vi hỏng rộng hơn lint:** ruff chết ở step 7 ⇒ step 8–11 skip ⇒ **`mypy`, `alembic upgrade`, `pytest` chưa từng chạy trên CI** suốt giai đoạn đó. Bằng chứng test giai đoạn đó là local-only.
- **Áp cho đúng 22 phase trước `01c2479`** — không phải giấy phép chung.

_Empty. Log ở đây khi Wyatt approve `RISK_WAIVER` để hạ tier dưới floor, hoặc skip test/gate với rationale._

---

## Resolved (chưa có)

_Empty. Khi issue chuyển RESOLVED, di chuyển vào đây kèm commit SHA + resolved-in-phase._

## ISSUE-023 — cap history 20 message / 4000 ký tự CHƯA ĐO (spec 10 H2)

**Trạng thái:** OPEN · **Mở:** 2026-07-20 · **Cùng họ:** ISSUE-022 (cap persona 2000 ký tự)

`agent/orchestrator.HISTORY_MAX_MESSAGES = 20` và `HISTORY_MAX_CHARS = 4000` (PRE-1003, Wyatt
ký 2026-07-20) suy từ ước lượng ký tự→token tiếng Việt ≈ 3.3 — **chưa chạy tokenizer
Llama-3.3 thật lần nào**. 4000 ký tự ≈ 1800 token là con số giấy tờ, không phải số đo.

Đặt số để có ràng buộc cứng từ đầu còn hơn để trôi. Nhưng đừng trích nó như đã đo: nếu tỉ lệ
thật lệch đáng kể thì hoặc ngân sách token vỡ (cap quá rộng), hoặc AI mất ngữ cảnh sớm hơn
cần thiết (cap quá hẹp) — cả hai đều không có triệu chứng rõ, chỉ làm chất lượng trả lời tệ đi.

**Đóng khi:** chạy tokenizer thật trên ≥50 hội thoại Zalo thật, đo phân phối token/message,
chốt lại hai số. Cùng lúc với ISSUE-022 (cả hai chia chung một ngân sách prompt).

**Chia làm hai câu hỏi khác độ khó (audit 2026-07-21):**
- **Q1 — tỉ lệ ký tự→token 3.3 có đúng?** Cần tokenizer + text VN đại diện, KHÔNG cần hội thoại
  thật. Offline kẹt (Llama-3.3 tokenizer là gated HF repo; `transformers` chưa cài). Đo được qua
  `usage.prompt_tokens` của provider (live). Harness: `tests/test_history_cap_tokens.py`
  (`@pytest.mark.live`, delta method khử overhead template) — một lệnh:
  `pytest tests/test_history_cap_tokens.py -m live -q -s`. Bind vào `HISTORY_MAX_*` thật.
- **Q2 — phân phối token/message trên hội thoại thật?** HARD-BLOCKED: 0 shop, PRE-004. Không bịa.
- ISSUE-023 CHỈ đóng khi có Q2. Q1 chỉ de-risk (bắt lỗi tỉ lệ thô); chạy Q1 → ghi số đo vào đây,
  KHÔNG đóng issue.

**Q1 ĐO THẬT (2026-07-21, Together Llama-3.3, delta 400↔2000 ký tự):**
- **3.55 ký tự/token** (giả định cũ 3.3 — sát, lệch ~8%, tỉ lệ đứng vững).
- `HISTORY_MAX_CHARS=4000` ⇒ **~1128 token thật**. Đính chính: câu "4000 ký tự ≈ 1800 token" ở
  §mở đầu issue này gán NHẦM — 1800 là ngân sách **GỘP** persona(2000)+history(4000)=6000 ký tự
  (6000/3.3 = 1818), và `agent/persona.py` khai đúng như vậy. History 4000 một mình ≈ 1128 token
  (đo) hay 1212 (giấy tờ 3.3). Thiết kế nhất quán; chỉ prose ISSUE-023 tách nhầm số gộp thành số
  riêng. Cap không làm vỡ ngân sách token; nếu lệch thì lệch phía bảo thủ.
- ⚠️ **Caveat:** đo trên text tiếng Việt LẶP (câu mẫu nhân bản). BPE merge trên chuỗi lặp có thể
  hiệu quả hơn hội thoại thật đa dạng ⇒ 3.55 có thể LẠC QUAN; hội thoại thật có thể nhiều
  token/ký tự hơn. Đây chính là lý do Q2 (hội thoại thật) vẫn cần trước khi chốt cap.

---

## ISSUE-024 — `api/webhook.py` khai Protocol `_Drafter` đã lệch với `agent.orchestrator.Drafter`

**Trạng thái:** ✅ ĐÓNG 2026-07-20 (cùng ngày mở) · **Mở:** 2026-07-20 (spec 10 H2)

**Vá:** xoá bản sao, `api/webhook.py` import thẳng `Drafter` từ `agent.orchestrator`.
Toàn repo giờ còn ĐÚNG MỘT khai báo — kiểm bằng
`grep -rn "class .*Drafter.*Protocol" --include="*.py" .`

⚠️ **Bảo đảm ở đây là CẤU TRÚC, không phải checker.** `api/` nằm NGOÀI scope mypy của
GATE_FULL (`mypy app agent retrieval parsing storage db bridge tools`), nên nếu để hai bản
khai thì không có gate nào bắt được lệch — đúng như đã xảy ra. Vá đúng không phải "đồng bộ
lại hai bản" mà là "bỏ bản thứ hai": một khai báo thì không có gì để lệch, kể cả khi không
ai chạy type-checker.

**Bài học giữ lại:** `# type: ignore[no-untyped-def]` làm mypy bỏ qua so khớp chữ ký. Mỗi
`type: ignore` là một điểm mù có chủ đích — dán nó lên một Protocol nghĩa là tắt đúng cái
kiểm tra mà Protocol sinh ra để làm.

`agent/orchestrator.Drafter.draft()` nhận thêm `history` từ H2. Bản sao `_Drafter` tại
`api/webhook.py:33` vẫn khai 3 tham số. **mypy không bắt được** vì dòng đó mang
`# type: ignore[no-untyped-def]` (return type untyped ⇒ bỏ qua so khớp).

Hệ quả: ai viết `Drafter` thật dựa theo Protocol của webhook sẽ qua type-check rồi nổ
`TypeError` lúc chạy khi orchestrator gọi kèm `history=`. Chưa chảy máu vì webhook chưa mount
và chưa có `Drafter` implementation nào.

Không vá trong H2 vì `api/webhook.py` ngoài `ALLOWED_FILES`. **Nguyên nhân gốc là sự TRÙNG
LẶP** — hai bản khai của cùng một khái niệm, sửa một dòng chỉ đồng bộ được tới lần đổi sau.
Cách đóng đúng: webhook import thẳng `Drafter` từ `agent.orchestrator`, xoá bản sao.

## ISSUE-025 — `agent/drafter.py` + `tests/test_drafter.py` ship format-dirty (spec 13)

**Trạng thái:** ✅ ĐÓNG 2026-07-21 (spec 14 A0) · **Mở:** spec 13 D0/D1 (`dc282b4`/`77c60c1`)

Spec 13 checkpoint DONE hai file với `ruff format --check .` ĐỎ — `git show HEAD:agent/drafter.py
| ruff format --check` xác nhận, ruff đúng bản pin `0.15.22`. Đây là hình dạng ISSUE-019 (gate
ký DONE trong khi thực ra đỏ): `GATE_FULL` có `ruff format --check` mà vẫn qua ⇒ hoặc checkpoint
spec 13 không chạy đủ bước, hoặc chạy trên state khác.

**Vá:** `ruff format` hai file (cơ học thuần, ZERO đổi hành vi — diff chỉ whitespace/wrap), fold
vào spec 14 A0 checkpoint qua `ALLOWED_FILES_AMEND` (Wyatt duyệt option 1). Un-break `GATE_FULL`
chung cho mọi phase sau.

**Bài học:** một gate đỏ trên HEAD chặn checkpoint của MỌI phase kế — không phải nợ của người
gây ra, mà là thuế của người kế tiếp. Gate phải là hàm của source; format-check phải xanh lúc
checkpoint chứ không phải "sửa sau".

## ISSUE-026 — 5 nợ RUNTIME của schema spec 14 (schema sẵn, chưa ai tiêu thụ)

**Trạng thái:** 🟡 MỞ 2026-07-21 (spec 14 A0+B0 DONE) · cùng hình dạng "persona chưa có Drafter" (spec 11)

Spec 14 CỐ Ý chỉ dựng SCHEMA (workflow §7: "sai schema từ đầu là refactor lớn"). Cột/bảng đã
sẵn nhưng ĐƯỜNG GHI chưa tồn tại — ghi ra để không trôi:

1. **ACK-then-process + queue + worker drain** (`GD0-INGEST` runtime) — webhook hiện draft INLINE;
   chưa có queue. `record_event` (spec 14 B0) chưa được gọi ở đâu.
2. **Snapshot CAPTURE lúc draft** — cột `pending_reply.snapshot` nullable sẵn; `agent/orchestrator.py`
   chưa ghi dữ kiện tầng-1 T0 vào đó. Đường ghi tương lai PHẢI validate lúc GHI (bài học spec 11).
3. **TTL computation + cron expiry** — cột `expires_at` sẵn; chưa tính `min(window, ngưỡng shop)`,
   chưa có cron chuyển `pending`→`expired`.
4. **Edit-path `label='edited'`** — CHECK nhận giá trị đó; chưa có edit endpoint nào ghi nó.
   Hiện chỉ approve/reject set label ⇒ auto-send GĐ1 thiếu tín hiệu `edited` tới khi edit UI land.
5. **`webhook_event_log` retention** — bảng append-only, chưa có cleanup ⇒ `GD3-HARDEN` (log retention).

Wire các phần này là `GD0-INGEST` runtime + `GD0-DRAFTSCHEMA` capture, mỗi cái một spec riêng
khi có người tiêu thụ (webhook mount cần PRE-004 ở Tân).
