# 07-Task-OhanaAISeller-GeneralChat

<!-- spec-generator v2.3 · Branch B (Roadmap v4 §3.0 ưu tiên-1 + P0 audit main-loop 2026-07-18) -->
<!-- PROJECT: Ohana AI Seller. NOT ONFA wallet. §4 dùng safety→trust→stability→growth. -->
<!-- ADP:MANIFEST inherited từ ohana-ai/CLAUDE.md §5, + `api/chat.py` (endpoint LLM có auth — cùng hạng với api/inbox.py):
GATE_RUNNER: .venv/bin/python -m pytest -q -x
RISK_PATHS: agent/orchestrator.py, agent/policy_gate.py, tools/registry.py, bridge/, auth/, db/migrations, api/webhook.py, api/inbox.py, api/admin.py, api/chat.py
SPEC_DIR: docs/tasks
EXECUTOR_SKILL: drnick-coder
CHECKPOINT_PREFIX: adp
-->

## §0 — Header

| Field | Value |
|---|---|
| Title | General Chat — seller ↔ AI qua Together LLM (Roadmap v4 §3.0 **ưu tiên 1**) |
| Parent | GĐ0 MVP Wedge — lát cắt ship được NGAY, không chờ Tân |
| Depends-on | Spec 06 Foundation (3/3 DONE). **KHÔNG** cần PRE-002/003/004, **KHÔNG** cần embedding, **KHÔNG** cần ADR PRE-007 ký |
| Unblocks | Dogfooding thật + de-risk toàn bộ tích hợp Together end-to-end trước khi tính năng chính cần nó |
| Owner | R: Tân (dev lead) · A: Wyatt (RISK finalize) |
| Branch | `main` (commit thẳng — khớp thực tế spec 06, KHÔNG khai branch không tồn tại) |
| Duration | 2–3 ngày |
| Spec type | Full · Workflow mode: IMPLEMENT |

---

## §1 — Problem Statement

Toàn bộ "tính năng chính" của GĐ0 (Wiki-RAG grounded reply → F2 tools → policy-gate → Zalo) **khoá cứng vào Tân** (PRE-002 REST API, PRE-003 wiki corpus, PRE-004 Zalo creds). Chờ = đứng im vô thời hạn.

Roadmap v4 §3.0 tách một lát cắt ship được ngay: **seller chat trực tiếp với AI trong app**, blocker duy nhất là Together key — **Wyatt đã cấp** (`TOGETHER_API_KEY` có trong `.env`, verified 2026-07-18).

**Audit on-disk 2026-07-18 — cái đã có và cái thiếu:**

1. **`agent/llm_client.py` đã có abstraction đủ dùng** — `LLMClient` ABC (3 abstract: `stream`/`complete`/`step`) + `ChatMessage`/`AssistantStep`/streaming delta types. Không cần thiết kế lại.

2. **`agent/providers/openai_client.py` = 380 dòng ĐÃ implement xong `LLMClient`, và ĐÃ nhận `base_url`** (dòng 112, 120-121: `AsyncOpenAI(api_key=…, base_url=base_url)`). Together là **OpenAI-compatible** → trỏ `base_url` là chạy.

3. **Nhưng module đó unimportable** vì đúng **1 import + 1 lời gọi**:
```
dòng 32:  from app import alert_service          # module chưa port (ISSUE-010)
dòng 134: await alert_service.record_provider_429()   # đếm 429 rồi re-raise NGUYÊN
```
Một counter telemetry fire-and-forget đang khoá chết 380 dòng client đã viết xong. Viết `together_client.py` độc lập theo đúng chữ Roadmap §3.0 sẽ **nhân bản 380 dòng** xử lý streaming/tool-call — nợ ngay ngày đầu. **Wyatt chốt phương án A (2026-07-18): gỡ coupling, tái dụng.**

4. **Thiếu hoàn toàn:** field Together trong `app/config.py` · `api/chat.py` · màn Chat trong `web/src/screens/` (đang có 4 màn: ChannelPicker · Inbox · ReviewCard · AdminWikiIngest).

5. **`tests/test_config.py` có `xfail(strict=True)`** khẳng định `openai_client` KHÔNG import được. Khi G0 gỡ coupling, test đó sẽ **XPASS** → `strict=True` biến XPASS thành **FAIL**. Đây là test làm đúng việc của nó; G0 phải cập nhật nó, KHÔNG được xoá.

---

## §2 — Goal

**VI:** Seller đăng nhập vào app, mở màn Chat, gõ câu hỏi, nhận phản hồi THẬT từ Together LLM — end-to-end, có auth, có đo token/cost/latency. Đồng thời **ép ranh giới an toàn bằng test**: general chat KHÔNG được với tới đường gửi khách.

**EN:** A logged-in seller opens a Chat screen, types, and gets a real Together-LLM response end-to-end — authenticated, with token/cost/latency measured. The safety boundary (general chat must never reach the customer-send path) is enforced by a gate test, not by a comment.

---

## §3 — Scope

### Sub-task A — Provider layer (Phase G0)
- Gỡ coupling module-level `alert_service` khỏi `OpenAIClient`: thay bằng hook **injected** `on_rate_limit: Callable[[], Awaitable[None]] | None = None`, mặc định `None`. Hành vi 429 giữ NGUYÊN (re-raise, không nuốt, không retry).
- `TogetherClient` = subclass mỏng, đặt `base_url` Together + model từ settings.
- `app/config.py` += `together_api_key`, `together_model`.
- Cập nhật `tests/test_config.py` xfail (xem §1.5).
- Files: `agent/providers/{openai_client,together_client}.py`, `app/config.py`, `tests/test_together_client.py`, `tests/test_config.py`.

### Sub-task B — Endpoint (Phase G1)
- `api/chat.py`: `POST /api/chat` — auth qua `identity_from_cookie`, **`shop_id` LẤY TỪ JWT**, không bao giờ từ body (R1.1). CSRF double-submit như các route mutating khác.
- Mount trong `app/main.py` — **TRƯỚC** `StaticFiles` catch-all (mount sau sẽ bị nuốt).
- Observability cơ bản: log `model_id` · `token_in/out` · `latency_ms` · `shop_id` mỗi request.
- **Gate ranh giới:** test đọc import-graph của `api/chat.py`, FAIL nếu nó với tới sender / `PendingReply` / `policy_gate`.
- Files: `api/chat.py`, `app/main.py`, `tests/test_chat_endpoint.py`.

### Sub-task C — UI (Phase G2)
- `web/src/screens/Chat.tsx` + CSS theo Astronixa tokens, tái dụng shell spec 04.
- `web/src/lib/api.ts` += `postChat()` qua `apiFetch` (CSRF tập trung sẵn).
- `web/src/App.tsx` thêm màn vào state-based routing (KHÔNG thêm react-router).
- Files: `web/src/screens/Chat.{tsx,css}`, `web/src/lib/api.ts`, `web/src/App.tsx`, `web/dist/` (build committed).

### Out of scope (cố ý — Roadmap v4 §3.0 "Scope OUT")
- ❌ Gửi tới khách / Zalo / webhook (PRE-004). **Đây là ranh giới an toàn, không phải cắt cho nhẹ.**
- ❌ Wiki-RAG grounding (PRE-003) · ❌ F2 tools (PRE-002) · ❌ intent classifier / escalation.
- ❌ policy-gate-to-customer — general chat là seller↔AI nội bộ, KHÔNG phải reply khách.
- ❌ Embedding / F1 swap sang e5 — General Chat không dùng embedding ⇒ **ADR PRE-007 chưa ký KHÔNG chặn phase này**.
- ❌ Credit metering (PRE-008) · ❌ streaming UI (dùng response 1 lần cho G2; streaming để phase sau).
- ❌ Port `app/alert_service.py` — G0 chỉ gỡ coupling, ISSUE-010 vẫn OPEN cho phần alerting thật.

---

## §4 — Safety Gate Check (Ohana axes)

Priority order: **safety → user trust → stability → growth**.

| Trục | Đánh giá | Verdict |
|---|---|---|
| **Safety** | Rủi ro #1 = **trượt ranh giới**: general chat (không grounded) bị dùng để soạn reply gửi khách → bịa giá/tồn kho tới khách thật. Roadmap §3.0 nói thẳng "không được trượt ranh giới này". Mitigation: **gate test import-graph** — `api/chat.py` chạm sender/`PendingReply`/`policy_gate` là ĐỎ. Không có đường HTTP nào từ chat tới khách. | ⚠️ FLAG — gate ranh giới là điều kiện DONE của G1 |
| **User trust** | Seller biết đây là AI tổng quát, không phải câu trả lời có căn cứ. Response mang cờ `grounded: false` tường minh để consumer sau không nhầm. UI phải nói rõ (§9). | PASS (điều kiện §9 i18n) |
| **Stability** | G0 biến 380 dòng client chết → sống, giảm nợ. Không đụng `agent/orchestrator.py` / `policy_gate.py`. Endpoint mới độc lập, hỏng thì chỉ hỏng màn Chat. | PASS |
| **Growth** | Đây CHÍNH LÀ đòn bẩy growth: dogfooding thật + de-risk Together end-to-end trước khi tính năng chính cần nó. | PASS |

**RED FLAG scan:**
- [x] Auto-send tới khách → **KHÔNG có đường nào**. Ép bằng gate test import-graph, không bằng comment.
- [x] `shop_id` từ body → **cấm**; chỉ từ JWT verified. Adversarial test bắt buộc (body claim shop khác JWT).
- [x] Endpoint không auth → `identity_from_cookie` + CSRF; test missing-cookie → 401, missing-CSRF → 403.
- [x] Fact hallucination → **chấp nhận có chủ ý** ở general chat (không grounded), NHƯNG phải hiện rõ cho seller (§9) và không được rò sang đường gửi khách.
- [x] Key rò → `TOGETHER_API_KEY` chỉ đọc từ env qua `Settings`, không log, không trả về response.
- [ ] ⚠️ **KHÔNG mitigate được bằng code:** seller tự dán PII khách vào ô chat → data đó sang Together-US. Đây là vấn đề consent/product, không phải kỹ thuật. §1.5 Roadmap (TIA + consent) áp khi có user VN thật. **Ghi vào §12, không giả vờ test che được.**

**VERDICT: FLAG** — ship được; gate ranh giới (G1) là acceptance-blocking.

---

## §5 — Source Files & Context (đọc trước khi action)

- `agent/llm_client.py` — `LLMClient` ABC + `ChatMessage`/`AssistantStep`. **KHÔNG sửa** (contract chung).
- `agent/providers/openai_client.py` — 380 dòng, sẽ gỡ coupling `alert_service` (G0).
- `app/config.py` — `Settings(BaseSettings)`; thêm 2 field Together. Nhớ: field kiểu phức parse bằng JSON (xem `.env.example` cảnh báo `REASONING_MODELS`).
- `auth/identity.py` — `identity_from_cookie`, `Identity(user_id, shop_id, role)`. **KHÔNG sửa** (RISK_PATH; chỉ import).
- `api/inbox.py` — mẫu router có auth + CSRF; `api/chat.py` follow cùng shape.
- `app/main.py` — thứ tự mount; `StaticFiles` PHẢI ở cuối.
- `web/src/lib/api.ts` + `App.tsx` + `screens/Inbox.tsx` — mẫu để viết màn Chat.
- `.env.example` — convention: secret để RỖNG.
- **[CANONICAL]** `~/Desktop/Ohana/Roadmap.md` v4 §3.0 (scope) + §1.5 (residency/provider).

---

## §6 — Pre-flight Checks (binary VERIFY)

```
PRE-G01: Together key HỢP LỆ (không chỉ "có mặt").
  Command: gọi thật endpoint models của Together bằng key trong .env, xác nhận HTTP 200.
  Expected: 200 + danh sách model. If fail (401/403): STOP G0 — key sai/hết hạn, Wyatt cấp lại.
  ⚠️ KHÔNG in key ra output.

PRE-G02: Chốt model LLM cho General Chat.
  Command: Wyatt chọn 1 model open-weight, ưu tiên tiếng Việt tốt.
           ⚠️ "Có trong /v1/models" KHÔNG đủ — danh sách đó gồm cả model chỉ chạy
           trên dedicated endpoint (Qwen2.5-72B-Turbo có mặt, kèm giá, vẫn 400).
           Điều kiện nghiệm thu là một CUỘC GỌI THẬT trả 200 kèm content khác rỗng.
  Expected: 1 chuỗi model id đặt vào TOGETHER_MODEL + live smoke PASS.
  If fail: G0 vẫn land được với default trong config (swappable qua env), nhưng
           ghi KNOWN UNCOVERED "model chưa chốt, chưa đo chất lượng tiếng Việt".
  Note: eval-SEED (spec 03d-D3) chưa tồn tại ⇒ chưa có cách ĐO. Đây là chọn tạm có chủ ý.

PRE-G03: Xác nhận hệ quả xfail.
  Command: grep xfail trong tests/test_config.py; xác nhận test khẳng định openai_client
           KHÔNG import được, và strict=True.
  Expected: tìm thấy → G0 PHẢI cập nhật nó (XPASS = FAIL khi strict). KHÔNG xoá test.
```

---

## §7 — Execute Steps (TDD gate RED trước impl)

### Phase G0 — Together client + config
<!-- ADP:PHASE G0 -->
STATUS: DONE
EVIDENCE: commit=a6a0814, gate_exit=0, duration=3s, review=PASS(judge=APPROVE,model=output-evaluator (haiku) — 3 rounds,bound=164b9cf5803e,tier=medium), ran=2026-07-19T01:51
GOAL: `TogetherClient` implement `LLMClient`, trỏ Together base_url, model + key từ `Settings`; `OpenAIClient` hết coupling module-level `alert_service` (hành vi 429 KHÔNG đổi); `tests/test_config.py` xfail cập nhật cho khớp thực tế mới.
APPROACH: `OpenAIClient.__init__` nhận `on_rate_limit: Callable[[], Awaitable[None]] | None = None`; `_create` gọi hook nếu có rồi **re-raise nguyên** (không nuốt, không retry — giữ y hệt hành vi cũ). Bỏ `from app import alert_service` + `type: ignore` kèm nó (F2 thêm ignore đó, giờ thành thừa). `TogetherClient(OpenAIClient)` đặt `base_url="https://api.together.xyz/v1"` + `api_key=settings.together_api_key` + `model=settings.together_model`. `app/config.py` += 2 field. **KHÔNG port `alert_service`** — ISSUE-010 vẫn OPEN cho phần alerting.
ALLOWED_FILES: agent/providers/openai_client.py, agent/providers/together_client.py, app/config.py, tests/test_together_client.py, tests/test_config.py, docs/reviews/, docs/tasks/07-Task-OhanaAISeller-GeneralChat.md
GATE: .venv/bin/python -m pytest tests/test_together_client.py tests/test_config.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools && .venv/bin/ruff check . && .venv/bin/ruff format --check .
RETRY: 0/3
RISK: medium (Wyatt ký 2026-07-18 — `agent/providers/` KHÔNG trong RISK_PATHS, nhưng đây là provider mới + đụng client 380 dòng)
BLOCKED_BY: (đã gỡ) PRE-G01 ✅ key hợp lệ · PRE-G03 ✅
REVIEW: PASS ref=docs/reviews/2026-07-19-spec07-G0.json
<!-- /ADP -->

1. `tests/test_together_client.py` (RED): (a) `TogetherClient` là `LLMClient`; (b) trỏ đúng Together base_url; (c) đọc key/model từ `Settings`, KHÔNG hardcode; (d) 429 vẫn re-raise nguyên, hook được gọi nếu inject, KHÔNG vỡ khi hook=None; (e) key KHÔNG xuất hiện trong `repr()`/log.
2. Cập nhật `tests/test_config.py` xfail → assert `openai_client` GIỜ import được (đảo ý nghĩa test, giữ nguyên ý định: theo dõi ISSUE-010).
3. `OpenAIClient`: thêm `on_rate_limit`, bỏ import module-level.
4. `TogetherClient` + 2 field config.
5. **STOP+WAIT** (ANCHOR — RISK medium).

### Phase G1 — `POST /api/chat` + ranh giới an toàn
<!-- ADP:PHASE G1 -->
STATUS: DONE
EVIDENCE: commit=3b1883d, gate_exit=0, duration=3s, review=PASS(judge=APPROVE,model=output-evaluator (haiku) — 3 rounds,bound=427f4c2f9f62,tier=medium), ran=2026-07-19T09:38
GOAL: Seller đã đăng nhập POST `/api/chat` nhận phản hồi thật từ Together; `shop_id` chỉ từ JWT; thiếu cookie → 401, thiếu CSRF → 403; body claim `shop_id` khác JWT → dùng JWT; **gate ranh giới: `api/chat.py` KHÔNG với tới sender/`PendingReply`/`policy_gate`**; log `model_id`/`token_in`/`token_out`/`latency_ms`/`shop_id`.
APPROACH: `api/chat.py` follow shape `api/inbox.py` (router builder + `identity_dep`). LLM client **inject qua tham số** để test dùng fake, không gọi mạng. Mount trong `app/main.py` TRƯỚC `StaticFiles`. Response `{reply, model, grounded: false, usage:{...}}` — cờ `grounded` tường minh để consumer sau không nhầm. Gate ranh giới đọc module `api.chat` + toàn bộ import transitive, FAIL nếu chạm `bridge.*sender*` / `PendingReply` / `agent.policy_gate`.
ALLOWED_FILES: api/chat.py, app/main.py, tests/test_chat_endpoint.py, app/config.py, agent/providers/together_client.py, tests/test_together_client.py, tests/test_together_live.py, tests/test_config.py, .env.example, docs/reviews/, docs/tasks/07-Task-OhanaAISeller-GeneralChat.md
SCOPE_EXTENSION (Wyatt duyệt 2026-07-19): +5 file để vá lỗi G0 phát hiện lúc smoke thật ở G1. `.env` có `TOGETHER_MODEL=` RỖNG → chuỗi rỗng ghi đè default trong `Settings` → `default_model or settings.together_model` = "" → `OpenAIClient` fallback tiếp `"" or settings.openai_model` ⇒ **TogetherClient gọi Together bằng `gpt-4o-mini`**, 404 `model_not_available`. 90/90 test xanh vì fake client không chạm model id thật. Hai khuyết tật: (1) env rỗng âm thầm thắng default — áp cho MỌI field str có default; (2) fallback rò sang provider khác — TogetherClient lẽ ra không có đường nào tới `openai_model`. Kèm live gate `tests/test_together_live.py` (`@pytest.mark.live`, deselect khỏi CI) vì đây là lớp lỗi fake KHÔNG BAO GIỜ bắt được. **+`tests/test_config.py`** (thêm sau review vòng 1): validator blank-env chạm path bảo mật `get_jwt_secret()`; ban đầu tôi chỉ kiểm tay rồi ghi kết quả vào comment — reviewer đúng khi từ chối coi đó là bằng chứng. Đã chuyển thành test thật.
GATE: .venv/bin/python -m pytest tests/test_chat_endpoint.py tests/test_together_client.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools && .venv/bin/ruff check . && .venv/bin/ruff format --check .
RETRY: 0/3
RISK: medium (Wyatt ký 2026-07-18 — `api/chat.py` thêm vào RISK_PATHS ở MANIFEST spec này: endpoint có auth gọi LLM, cùng hạng `api/inbox.py`; floor ⇒ ≥medium)
BLOCKED_BY: G0
REVIEW: PASS ref=docs/reviews/2026-07-19-spec07-G1.json
<!-- /ADP -->

6. `tests/test_chat_endpoint.py` (RED): (a) happy path với fake client → 200 + reply; (b) không cookie → 401; (c) không CSRF header → 403; (d) **adversarial**: body `{"shop_id":"X"}` + JWT shop=Y → dùng Y; (e) **gate ranh giới** import-graph; (f) `grounded` là `false` trong response.
7. `api/chat.py` implement.
8. Mount trong `app/main.py` (trước StaticFiles) + verify thứ tự.
9. Observability logging.
10. **STOP+WAIT** (ANCHOR).

### Phase G2 — Màn Chat
<!-- ADP:PHASE G2 -->
STATUS: IN_PROGRESS
GOAL: Seller mở màn Chat trong app, gõ, thấy phản hồi; UI nói RÕ đây là AI tổng quát không có căn cứ dữ liệu shop; build `web/dist/` xanh; toàn suite vẫn xanh.
APPROACH: `Chat.tsx` tái dụng shell + Astronixa tokens spec 04 (KHÔNG token mới). Gọi qua `apiFetch` (CSRF đã tập trung sẵn). State-based routing như 4 màn hiện có, KHÔNG thêm react-router. Disclaimer VI hiện thường trực, không phải tooltip ẩn.
ALLOWED_FILES: web/, tests/test_chat_ui.py, docs/reviews/, docs/tasks/07-Task-OhanaAISeller-GeneralChat.md
GATE: .venv/bin/python -m pytest tests/test_chat_ui.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/ruff check . && env PATH="/Users/wyattngo/.nvm/versions/node/v23.6.1/bin:$PATH" pnpm --dir web build
RETRY: 1/3
RISK: low (Wyatt tick 2026-07-19 — `web/` không giao RISK_PATHS; không có đường tới khách)
BLOCKED_BY: G1
REVIEW: PASS ref=docs/reviews/2026-07-19-spec07-G2.json
<!-- /ADP -->

11. `tests/test_chat_ui.py` (RED): contract FE↔BE (shape response khớp cái `api.ts` bind).
12. `Chat.tsx` + CSS + wire `api.ts` + `App.tsx`.
13. `pnpm build` (⚠️ `nvm use v23.6.1` — system node v16 quá cũ cho Vite 8).
    **GATE_FULL sửa 2026-07-19 (RETRY 1/3):** bản đầu ghi `cd web && pnpm build`, và checkpoint ĐỎ —
    nhưng đỏ ở chính câu lệnh gate, không phải ở code. `pnpm` trên PATH thuộc node v20.20.2, corepack
    bản đó thiếu `URL.canParse` (cần node ≥22) ⇒ `TypeError` trước khi build kịp chạy. Nghĩa là gate
    đang đo **trạng thái shell lúc chạy** chứ không đo build: nó xanh với tôi chỉ vì tôi `nvm use`
    trước. Đã ghim toolchain — `env PATH="…/v23.6.1/bin:$PATH" pnpm --dir web build` — cùng cách
    `.claude/launch.json` đã ghim sẵn. Đây là làm gate **tái lập được**, KHÔNG phải nới gate: build vẫn
    phải xanh y như cũ (đã kiểm: exit 0).
14. **STOP+WAIT**.

---

## §8 — DB Changes

**KHÔNG CÓ.** General Chat không persist gì ở phase này — không lưu lịch sử chat, không `credit_ledger`, không đụng `conversations`/`customers` (đó là hội thoại KHÁCH, không phải seller↔AI; trộn 2 thứ vào một bảng là sai mô hình).

Lưu lịch sử chat seller = phase sau, cần quyết định retention + residency trước (§1.5 Roadmap).

---

## §9 — i18n Keys

- Disclaimer thường trực trên màn Chat — VI-first, đại ý: *"Trợ lý AI tổng quát. Chưa kết nối dữ liệu shop của bạn — đừng dùng câu trả lời này để trả lời khách."* Đây là **yêu cầu an toàn**, không phải trang trí: nó là thứ chặn seller copy-paste sang khách.
- Nhãn lỗi: mất mạng / provider 429 / quá dài.
- KHÔNG hardcode string trong component — theo cơ chế i18n spec 04.

---

## §10 — Post-checks

```
py_compile mọi file đổi
ruff check . && ruff format --check .
mypy app agent retrieval parsing storage db bridge tools
pytest -q -m 'not live' (toàn bộ)
cd web && pnpm build

Smoke thật (Wyatt/Tân, sau G2):
  đăng nhập dev → mở Chat → gõ "chào" → thấy phản hồi thật từ Together
  Expected: có reply, log hiện model_id + token_in/out + latency_ms

Gate ranh giới (bắt buộc, G1):
  pytest tests/test_chat_endpoint.py -k boundary
  Expected: PASS. Nếu ai nối general chat vào đường gửi khách → ĐỎ.

Adversarial:
  POST /api/chat body {"shop_id":"khac"} + JWT shop=A  → debit/scope theo A
  POST không cookie → 401 · POST không CSRF → 403
```

---

## §11 — Deliverables

- `TogetherClient` chạy thật; `OpenAIClient` hết coupling `alert_service` (hành vi 429 không đổi).
- `POST /api/chat` mounted, có auth + CSRF, `shop_id` từ JWT.
- Màn Chat trong `web/`, có disclaimer thường trực.
- Observability: model/token/latency mỗi request.
- Gate ranh giới xanh — có bằng chứng general chat không với tới khách.
- Commit pattern: `adp/07-GeneralChat phase-GN: <concern>`.

---

## §12 — Constraints (STOP + anti-patterns)

- **STOP+WAIT** sau mỗi phase; 1 confirm tại ANCHOR (RISK medium G0/G1).
- **ALLOWED_FILES hard-bound** — cần mở thì xin, không tự tiện (spec 06 đã phải xin 4 lần; xin sớm tốt hơn xin muộn).
- 🚫 **KHÔNG nối general chat vào bất kỳ đường gửi khách nào.** Đây là ranh giới Roadmap §3.0 nói "không được trượt". Ép bằng gate test.
- 🚫 **KHÔNG** đọc `shop_id`/`user_id`/`role` từ body — chỉ JWT verified.
- 🚫 **KHÔNG** log/trả về `TOGETHER_API_KEY` dưới bất kỳ dạng nào.
- 🚫 **KHÔNG** port `alert_service` trong spec này (ISSUE-010 giữ nguyên scope riêng).
- 🚫 **KHÔNG** thêm design token mới — dùng Astronixa đã frozen (DEC-OHANA-01 §U2).
- 🚫 **KHÔNG** lưu lịch sử chat (§8) — cần quyết retention + residency trước.
- ⚠️ **Rủi ro KHÔNG che được bằng code:** seller tự dán PII khách vào ô chat → sang Together-US. Vấn đề consent/product. §1.5 Roadmap (TIA + consent) áp khi có user VN thật. **Đừng giả vờ gate test che được cái này.**
- **Không self-certify DONE** — `adp-checkpoint.sh` quyết.

---

## §13 — Tracking

| Phase | Concern | RISK (proposed) | STATUS | BLOCKED_BY | EVIDENCE |
|---|---|---|---|---|---|
| PRE | G01 key hợp lệ · G02 chốt model · G03 xfail | — | TODO | Wyatt (G02) | — |
| G0 | TogetherClient + gỡ coupling + config | medium | TODO | PRE-G01 | — |
| G1 | `POST /api/chat` + gate ranh giới + observability | medium | TODO | G0 | — |
| G2 | Màn Chat + disclaimer | low | TODO | G1 | — |

---

## §14 — Assumptions & Open (Wyatt chốt trước execute)

**Wyatt ĐÃ KÝ 2026-07-18:**
- [x] ~~**PRE-G02 model = `Qwen/Qwen2.5-72B-Instruct-Turbo`**~~ ❌ **THU HỒI 2026-07-19 — model KHÔNG dùng được.** Together trả `400 model_not_available: non-serverless model … create a dedicated endpoint`. Lời khai "verified có trên Together" ở bản ký 18/07 là **SAI**: nó dựa trên việc model có mặt trong `/v1/models` (kèm cả bảng giá), nhưng danh sách đó liệt kê cả model chỉ chạy trên dedicated endpoint. **Danh sách model không phải bằng chứng về khả năng phục vụ — chỉ một cuộc gọi thật mới là.** Lỗi lọt qua 3 vòng review G0 vì mọi test đều tiêm fake client; fake không quan tâm model id có thật hay không.
- [x] **PRE-G02 (ký lại 2026-07-19) model = `meta-llama/Llama-3.3-70B-Instruct-Turbo`** ✅ — verified bằng **cuộc gọi thật**, không phải bằng danh sách. Dò 148 ứng viên chat ⇒ **6 model thật sự phục vụ**:

  | Model | $/M in→out | Bịa số liệu? | Reasoning? |
  |---|---|---|---|
  | `google/gemma-3n-E4B-it` | 0.06 → 0.12 | không | không |
  | `openai/gpt-oss-120b` | 0.15 → 0.60 | không | **có** |
  | `Qwen/Qwen2.5-7B-Instruct-Turbo` | 0.30 → 0.30 | **CÓ** ("2-3 ngày") | không |
  | `meta-llama/Llama-3.3-70B-Instruct-Turbo` ← **chọn** | 1.04 → 1.04 | không | không |
  | `deepcogito/cogito-v2-1-671b` | 1.25 → 1.25 | không | không |
  | `zai-org/GLM-5.2` | 1.4 → 4.4 | — | có (content rỗng) |

  Lý do chọn: **non-reasoning** (model reasoning trả `content` RỖNG khi `max_tokens` không đủ — Kimi-K2.6 đốt sạch 300 token vẫn rỗng, không exception; `api/chat.py` giờ bắt và trả 502, nhưng tránh vẫn hơn), không bịa số liệu dưới `_SYSTEM_PROMPT`, tiếng Việt đúng ngữ vực bán hàng ("Dạ", "anh/chị"), open-weight ⇒ giữ nguyên lập luận portability của ADR PRE-007. ~$0.36/1000 tin. ⚠️ Vẫn là **suy luận + smoke thủ công, KHÔNG phải eval-SEED** — chốt cuối ở Spec 03d-D3. Swappable qua `TOGETHER_MODEL`; đổi xong PHẢI chạy `pytest tests/test_together_live.py -m live`.
- [x] **Đo thật (2026-07-19, end-to-end qua `/api/chat` với Together thật):** cold start **24.8s**, call thứ hai **1.2s**. ⚠️ G2 phải có loading state thật — 25s không có phản hồi thị giác là hỏng UX.
- [x] **RISK tier:** G0 **medium** · G1 **medium** (Wyatt ký "risk medium" khi duyệt phương án A).
- [x] **G2 tier = `low`** ✅ Wyatt tick 2026-07-19 (chỉ `web/`, không giao RISK_PATHS, không có đường tới khách).
- [x] **`api/chat.py` vào RISK_PATHS** ✅ — endpoint có auth gọi LLM, cùng hạng `api/inbox.py`.
- [x] **Lịch sử chat: để phase sau** ✅ — cần quyết retention + residency trước (§1.5 Roadmap).

**PRE-flight đã chạy 2026-07-18:** PRE-G01 ✅ (HTTP 200, 272 model) · PRE-G03 ✅ (xfail strict tại `test_config.py:88`).

> RISK tier = **proposed**. EVIDENCE do `adp-checkpoint.sh` ghi. REVIEW do `adp-review.sh stamp`.
