# KNOWN_ISSUES — Ohana AI Seller

> Nơi log deferred bugs / assumption breaks / waivers / open PRE checks. Update mỗi sub-phase (ghi mới, KHÔNG xoá cũ — chỉ đổi STATUS + gắn resolved commit SHA).
>
> Last updated: 2026-07-18 · Status: Spec 01/02/04/05/06 DONE (ADP 18/28). mypy 0 lỗi (F2 đưa 12→0 — CI mypy trước đó ĐỎ âm thầm trên main). Contract gates all GREEN via mocks/fixtures; PRE-002/003/004 backfill deferred until source landed. Newly-tracked deferred items from Phase 2–5: HS256+exp/aud/iss upgrade (auth), send-on-approve worker (F3), shops/customers/conversations tables, wider F2 read-tools.

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
- **Status:** ⏳ PARTIAL — `app/config.py` half RESOLVED bởi spec 05 P0 (2026-07-17); `app/alert_service.py` half còn OPEN.
- **Detail:** `agent/providers/openai_client.py` imports `from app import alert_service` (line 28) + `from app.config import get_settings` (line 13). `agent/providers/openai_embedder.py` imports chỉ `from app.config import get_settings`. test_ports dùng `py_compile` (parse-only) nên GATE pass dù runtime-import vỡ.
- **Cập nhật 2026-07-19 (spec 07 G0) — COUPLING GỠ, ISSUE VẪN OPEN:** `OpenAIClient` KHÔNG còn import module-level `app.alert_service`; telemetry 429 thành hook tiêm `on_rate_limit` (`Callable[[], Awaitable[None]] | None`). Module import sạch, `TogetherClient` dựng được trên nó. `xfail(strict=True)` trong `tests/test_config.py` đã **ĐẢO CHIỀU** thành assertion thật (`test_openai_client_imports_without_alert_service`) — giữ test để chặn ai đó thêm lại import module-level vào thứ chưa tồn tại.
  - ⚠️ **VẪN OPEN:** `app/alert_service.py` CHƯA port. Hôm nay **429 không được đếm ở đâu cả** trừ khi caller tự tiêm hook — đây là capability regression spec 07 chấp nhận có ý thức, KHÔNG phải đã giải quyết.
- **Cập nhật 2026-07-17 (spec 05 P0):** `app/config.py` đã build (Settings 4 field). Hệ quả: `OpenAIEmbedder` (F1) giờ import + instantiate được — nửa embedder của ISSUE-010 + toàn bộ ISSUE-016 config-half GIẢI QUYẾT. NHƯNG `OpenAIClient` (LLM chat, F2/F3) VẪN vỡ vì `app/alert_service.py` chưa port. Encode ở `tests/test_config.py::test_openai_client_import_blocked_by_unported_alert_service` (`xfail(strict=True)` — flip hard-fail khi port xong, không rot).
- **Action còn lại:** port `app/alert_service.py` (fire-and-forget 429 counter — stub no-op OK ở MVP) — thuộc **LLM-client wiring spec** (F2/F3, cùng lúc wire `OpenAIClient` + concrete `Drafter` + webhook mount, gated PRE-004). KHÔNG thuộc spec 05 (F1 không cần LLM client). Khi làm: xoá xfail ở test_config.py.

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
- **Status:** ✅ RESOLVED 2026-07-19 — commit "fix(ci): pin ruff…" (action 1+2+3). Action 4 (rà phase DONE cũ) vẫn OPEN, xem cuối entry.
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

### ISSUE-017 — `channels/identity.py`: thiếu unique constraint → race có thể tạo 2 Conversation cho 1 khách
- **Origin:** spec 06 F1 (khai KNOWN UNCOVERED ngay trong code + review artifact `docs/reviews/06-F1-auto-verdict.json`)
- **Discovered:** 2026-07-18 · session spec-06-F1
- **Severity:** medium (chưa chạm được, nhưng chạm được ngay khi webhook mount)
- **Status:** OPEN
- **Detail:** `resolve_conversation()` upsert `Customer` bằng `ON CONFLICT DO NOTHING` trên `uq_customers_shop_chan_ext` (race-safe), NHƯNG phần `Conversation` là **select-then-insert** và bảng `conversations` KHÔNG có unique trên `(shop_id, customer_id, channel)`. Hai tin nhắn đến đồng thời từ cùng một khách → 2 Conversation.
- **Why not blocking now:** `api/webhook.py` **chưa mount** trong `app/main.py` (thiếu concrete `Drafter`), nên không luồng nào gọi hàm này đồng thời. Đây là lỗi TIỀM ẨN, không phải đang chảy máu.
- **Action:** Thêm Alembic migration `UNIQUE (shop_id, customer_id, channel)` trên `conversations` + đổi phần Conversation sang cùng shape upsert như Customer. **BẮT BUỘC làm TRƯỚC khi Spec 03c mount webhook** — đừng dựa vào "chưa xảy ra bao giờ".

### ISSUE-018 — `_blank_env_means_unset` KHÔNG phủ complex field; docstring khai "áp cho MỌI field" là SAI
- **Origin:** spec 07 G0 (`app/config.py`) — phát hiện khi so sánh 2 bản CLAUDE.md, 2026-07-19
- **Discovered:** 2026-07-19 · session claude-md-merge
- **Severity:** medium (không chảy máu prod hôm nay; là lỗ trong chính hàng rào dựng lên để chặn lớp bug này)
- **Status:** OPEN
- **Detail:** `_blank_env_means_unset` là `@model_validator(mode="before")`, lọc `""` khỏi dict input. Nhưng với field kiểu phức (`reasoning_models: frozenset[str]`), pydantic-settings `EnvSettingsSource` **parse JSON TRƯỚC** khi validator chạy ⇒ chuỗi rỗng nổ ngay tại tầng source, validator không bao giờ thấy. Kiểm thật:
  ```
  REASONING_MODELS= → SettingsError: error parsing value for field "reasoning_models"
                      from source "EnvSettingsSource"
  ```
  Nghĩa là hàng rào chỉ bảo vệ field vô hướng (`str`, `str | None`). Docstring hiện khai *"Áp cho MỌI field, không riêng Together"* — sai, và câu sai đó đã được chép nguyên vào CLAUDE.md, tức nó đang **nhân bản**. Đây đúng kịch bản `.env.example` mà spec 07 dựng hàng rào để chặn: admin copy template, để trống dòng chưa dùng → app không chạy, thông báo lỗi không nói gì về "để trống".
- **Why not blocking:** `reasoning_models` là field phức DUY NHẤT hiện tại, và `.env.example` không liệt kê `REASONING_MODELS`. Lỗi là fail-loud (raise lúc khởi động), không phải silent-wrong.
- **Action:** (1) Sửa docstring cho đúng phạm vi — ưu tiên cao hơn sửa code, vì docstring sai đang được chép đi. (2) Cân nhắc `settings_customise_sources` hoặc `NoDecode` + validator riêng để chuẩn hoá rỗng trước khi source parse. (3) Thêm test `REASONING_MODELS=` rỗng khoá hành vi đã chọn (dù chọn "raise" hay "coi như unset" — hiện KHÔNG có test nào chạm ca này).

### ISSUE-016 — F1 wiki-RAG chưa từng chạy với embedding thật (⚠️ ĐỔI BẢN CHẤT 2026-07-18: provider chuyển sang Together e5)

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

## Waivers / trade-offs (chưa có)

_Empty. Log ở đây khi Wyatt approve `RISK_WAIVER` để hạ tier dưới floor, hoặc skip test/gate với rationale._

---

## Resolved (chưa có)

_Empty. Khi issue chuyển RESOLVED, di chuyển vào đây kèm commit SHA + resolved-in-phase._
