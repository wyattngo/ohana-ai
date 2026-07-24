# 13-Task-OhanaAISeller-Drafter

<!-- adp-spec v2.3 · Wyatt directive 2026-07-21 "author GD0-DRAFTER" -->
<!-- PROJECT: Ohana AI Seller. NOT ONFA wallet. §4 trục safety→trust→stability→growth, -->
<!-- KHÔNG dùng Survival Framework — Ohana không có cột tài chính. -->

## §0 — Header

| Field | Value |
|---|---|
| Title | Concrete `Drafter` — LLM sinh draft giọng shop + intent/confidence structured, grounded qua tool |
| Parent | `GD0-DRAFTER` (L1 `docs/ROADMAP.md` §4.1) |
| Depends-on | Spec 07 (General Chat — `TogetherClient`, `llm.step`, DONE) · Spec 10 (History, DONE) · Spec 11 (persona + `lookup_size`/`lookup_shipping`, DONE) |
| Fills | Mảnh khuyết `agent/orchestrator.Drafter` (Protocol từ spec 01, **zero impl**) — flag ở spec 11 §1.3 |
| Unblocks | Mount `api/webhook.py` (điều kiện thứ 1/2 — điều kiện 2 là `GD0-ZALO`/PRE-004, kẹt Tân) · `GD0-EVAL` (cần draft thật để chấm) · `GD0-INTENT` (mở rộng intent tối thiểu → classifier 15 loại) |
| Owner | R: Claude (AI-coder) · A: Wyatt |
| Branch | `main` (commit thẳng — khớp spec 06–12) |
| Spec type | Feature · Workflow mode: IMPLEMENT |
| Migration | **KHÔNG** — Drafter thuần code, tiêu thụ `shops`/`shop_profile`/`Message` đã có. Không chạm `db/migrations`. |

---

## §1 — Problem Statement

### 1.1 `Drafter` là Protocol rỗng — cả sản phẩm treo ở đây

`agent/orchestrator.py:79` khai `class Drafter(Protocol)` với `async def draft(*, shop_id, customer_id, message, history) -> _Draft` (`_Draft` = `.text: str`, `.intent: str`, `.confidence: float`). **Không có một concrete impl nào** trong repo — `orchestrator.receive_and_draft` nhận `drafter` truyền vào, mọi test đều tiêm fake (`tests/test_message_history.py:234 _FakeDrafter`).

Hệ quả dây chuyền, xác nhận trên đĩa 2026-07-21:
- `api/webhook.py` **chưa mount** (`app/main.py:16` docstring nói thẳng: *"needs a concrete `Drafter`"*) → đường tin-khách-vào **zero traffic**.
- `agent/persona.build_persona_prompt` (spec 11) sinh prompt **chưa ai tiêu thụ**.
- last-N history (spec 10) nạp vào `draft()` **chưa ai đọc**.

Ba thứ đã build đều chờ đúng một mảnh: thứ biến `(persona + history + message)` → câu trả lời. Đó là spec này.

### 1.2 Ranh giới với `GD0-INTENT` — cố ý hẹp

L1 §4.1 ghi rõ: item này sinh `intent`+`confidence` **TỐI THIỂU** đủ cho `policy_gate.decide`, lấy từ **structured output của chính LLM**. Classifier 15 loại + suppress spam + confidence-gated escalation là `GD0-INTENT` (spec sau), **KHÔNG ở đây**. Hai item cùng chạm `intent`/`confidence` — ghi ranh giới để không dẫm chân như `GD0-SHOPS` ↔ spec 03 Phase 1.

Cụ thể "tối thiểu": `policy_gate.SENSITIVE_INTENTS = {complaint, refund, price_negotiation, specific_order}` + một mã trung tính (`general`). Drafter phải phát ra `intent` trong tập enum **bao trọn 4 mã nhạy cảm này** (nếu không, gate không bao giờ park được intent nhạy cảm) + `confidence ∈ [0,1]`.

### 1.3 Vì sao mount webhook KHÔNG nằm trong spec này

Mount cần **hai** điều kiện (orchestrator docstring + `webhook.py` docstring): (a) Drafter thật — spec này giao; (b) `GD0-ZALO`/PRE-004 (Zalo creds + signature verify) — **kẹt Tân**, external. Giao Drafter xong chỉ gỡ **một** trong hai. Mount + `enabled=True` thuộc `GD0-ZALO`. Spec này dừng ở: Drafter tồn tại, test qua `orchestrator.receive_and_draft` (fake sender), live-smoke trên model thật.

### Audit on-disk 2026-07-21 — HEAD `34a7ed4`, đo bằng lệnh thật

1. ✅ `agent/orchestrator.Drafter` Protocol, zero impl (`grep -rn "class .*Drafter" agent/ api/` = 2 hit: khai báo + import trong webhook).
2. ✅ `agent/persona.build_persona_prompt(persona_md, *, shop_display_name) -> str` — hàm thuần, cap `PERSONA_MAX_CHARS=2000`.
3. ✅ `agent/policy_gate.decide(DraftContext(confidence, intent, shop_auto_enabled_for_intent))` — intent khớp `SENSITIVE_INTENTS`, threshold `0.85`.
4. ✅ `agent/llm_client.LLMClient.step(messages, *, tools, model, temperature, max_tokens) -> AssistantStep` (`.content | .tool_calls | .usage`). `TogetherClient` = default `Llama-3.3-70B-Instruct-Turbo`.
5. ✅ `tools/shop_kb.build_size_tool/build_shipping_tool(session_factory) -> Tool`; handler `(user_id, shop_id, args)`, `shop_id` KHÔNG trong `parameters` (R1.1). `Tool.kind="read"` chạy trực tiếp.
6. ✅ `db/repos.ShopProfileRepo(session, *, shop_scope).get() -> ShopProfile | None` (`.persona_md`, `.knowledge`). Shop display_name: `db/models.Shop`.
7. ✅ `api/chat.py:112` mẫu tiêu thụ `await llm.step(messages)` + đọc `step.usage`/`step.content` — reuse pattern.
8. ✅ Không có `tests/test_drafter*.py`. Live-test convention: `-m live` (`test_together_live.py`, `test_wiki_rag_live.py`).

---

## §2 — Approach (quyết định thiết kế, mang *why*)

**Drafter đặt ở file MỚI `agent/drafter.py`.** KHÔNG nhét vào `orchestrator.py`: orchestrator quyết *gửi hay park*, Drafter quyết *nói gì*. Trộn hai vai làm import-graph gate (chat ↔ sender) khó giữ. `agent/drafter.py` **KHÔNG** trong RISK_PATHS theo path — nhưng RISK tier gán theo **bản chất** (§ RISK mỗi phase), không theo path.

**Structured output = một tool-loop với terminal tool `emit_reply` (approach C).** Ba lựa chọn cân nhắc:
- (A) forced `emit_reply` một lượt, không grounding — không tra được size/ship.
- (B) hai call: grounding loop rồi classify riêng — gấp đôi latency/cost mỗi tin.
- (C) **chọn** — một loop: model được offer grounding tools *(D1)* + một tool bắt buộc `emit_reply{text, intent(enum), confidence(number)}`; loop kết khi model gọi `emit_reply` (hoặc cap vòng lặp). `intent`+`confidence` = **args của `emit_reply`** ⇒ đến từ LLM, không hardcode. Một hội thoại, dùng đúng `llm.step(tools=...)` sẵn có.

**Vì sao `intent` là enum, không free-text:** `policy_gate` so khớp mã chính xác; free-text "khiếu nại" ≠ `complaint` sẽ **lọt gate** âm thầm (sensitive intent không park). Enum ép model chọn trong tập máy hiểu.

**`shop_id` xuống tool KHÔNG bao giờ từ LLM.** Khi model gọi `lookup_size` (D1), Drafter dispatch qua `Tool.handler(user_id, shop_id, args)` với `shop_id` từ **tham số `draft()`** (verified upstream), `args` chỉ mang field trong `parameters` (đã `additionalProperties:false`). Đây là R1.1 — model nhắc tên shop khác trong câu hỏi cũng không chĩa tool sang tenant khác được.

**Ranh giới an toàn (import-graph, như `api/chat.py`):** `agent/drafter.py` KHÔNG import `bridge.*sender*`, `channels.*`, `agent.policy_gate`, `PendingReply`. Drafter **chỉ sinh draft** — quyết gửi/park là của `orchestrator`. Test đi bao đóng import bắt vi phạm.

**Vì sao live-smoke là bắt buộc, không phải test thường:** test env tiêm `FakeLLMClient` — nó chứng minh Drafter *ráp prompt đúng* và *parse structured đúng*, nhưng KHÔNG chứng minh **model thật tuân** chỉ dẫn "không lộ danh tính". `agent/persona.py:38` docstring nói thẳng điều này: no-leak phải đo bằng `-m live` trên OUTPUT thật. Cùng họ `_DeterministicDevEmbedder`: sai kiểu này không đỏ test thường.

---

<!-- ADP:PHASE D0 -->
STATUS: DONE
EVIDENCE: commit=dc282b4, gate_exit=0, duration=13s, review=PASS(judge=APPROVE,model=claude-haiku-4-5-20251001,bound=7db0d49369b6,tier=high), smoke=PASS(bound=7db0d49369b6), ran=2026-07-21T15:04
ROADMAP: GD0-DRAFTER
GOAL: `agent/drafter.py` định nghĩa `LLMDrafter` implement `Drafter` (mypy structural check pass). `draft(*, shop_id, customer_id, message, history)` trả object `.text/.intent/.confidence` với intent+confidence LẤY TỪ args `emit_reply` của LLM (test: `FakeLLMClient` trả hai payload khác nhau ⇒ drafter surface đúng cả hai, chứng minh không hardcode). System prompt gửi tới LLM CHỨA `build_persona_prompt(profile.persona_md, shop_display_name=…)` (test capture messages). `history` xâu theo thứ tự vào messages. `intent` enum bao trọn `{complaint,refund,price_negotiation,specific_order,general}` (test assert schema enum ⊇ 4 mã nhạy cảm). Import-graph: `agent/drafter.py` KHÔNG import sender/channels/policy_gate/PendingReply (test bao đóng import, đỏ khi vi phạm). `pytest tests/test_drafter.py` xanh.
APPROACH: File mới `agent/drafter.py` (§2). `LLMDrafter(llm, session_factory)` — `draft()` load `ShopProfile`+`Shop.display_name` qua repo, `build_persona_prompt`, ráp `[system(persona), *history, user(message)]`, gọi `llm.step(messages, tools=[EMIT_REPLY_TOOL])` với `emit_reply{text,intent(enum),confidence}` bắt buộc, parse args → `_DraftResult`. Cap vòng lặp = 1 ở D0 (chưa grounding tool). intent+confidence = args ⇒ từ LLM. KHÔNG import đường-gửi (giữ ranh giới như `api/chat.py`).
ALLOWED_FILES: agent/drafter.py, tests/test_drafter.py, tests/test_drafter_live.py, docs/tasks/13-Task-OhanaAISeller-Drafter.md, docs/smokes/, docs/reviews/
GATE: .venv/bin/python -m pytest tests/test_drafter.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools api auth && .venv/bin/ruff check . --no-cache
RETRY: 0/3
RISK: high (AI-output code — `confidence` Drafter phát ra lái trực tiếp `policy_gate` auto_send; draft quá tự tin + sai trên intent không-nhạy-cảm ⇒ tự gửi tới khách thật. Roadmap §8 "AI overconfident sai" = HIGH. KHÔNG trong RISK_PATHS theo path nhưng tier theo bản chất; TDD RED-first + per-step confirm.)
SMOKE: PASS ref=docs/smokes/13-D0.md
REVIEW: PASS ref=docs/reviews/13-D0-auto-verdict.json human=docs/reviews/13-D0-human.md
<!-- /ADP -->

1. Test (**RED first**, RISK:high): `tests/test_drafter.py` — `FakeLLMClient` ghi lại `messages` nhận được + trả `AssistantStep` với `emit_reply` tool_call args. Assert: (a) hai payload khác nhau → hai `(intent,confidence)` khác nhau (không hardcode); (b) persona prompt xuất hiện trong system message; (c) history xâu đúng thứ tự; (d) enum ⊇ 4 mã nhạy cảm; (e) import-closure không chạm sender/channels/policy_gate. Confirm ĐỎ.
2. `agent/drafter.py`: `EMIT_REPLY_TOOL` schema + `LLMDrafter` + `_DraftResult` dataclass.
3. `draft()`: load profile/display_name → `build_persona_prompt` → ráp messages → `llm.step(tools=[EMIT_REPLY_TOOL])` → parse args. Xử lý model KHÔNG gọi `emit_reply` (fallback: raise rõ, KHÔNG trả confidence bịa).
4. Live-smoke `tests/test_drafter_live.py -m live` (chạy lúc DONE, không trong GATE_FULL).
5. **STOP+WAIT** cho checkpoint.

---

<!-- ADP:PHASE D1 -->
STATUS: DONE
EVIDENCE: commit=77c60c1, gate_exit=0, duration=14s, review=PASS(judge=APPROVE,model=claude-haiku-4-5-20251001,bound=a3417442de0c,tier=high), smoke=PASS(bound=a3417442de0c), ran=2026-07-21T15:30
ROADMAP: GD0-DRAFTER
GOAL: `LLMDrafter` offer thêm `lookup_size`/`lookup_shipping` (từ `tools/shop_kb`) vào cùng loop với `emit_reply`; chạy tool-call loop tất định. Câu hỏi size/ship ⇒ draft grounded trên tool result (test: `FakeLLMClient` phát `lookup_size` tool_call trước rồi `emit_reply`; drafter dispatch handler với `shop_id` TỪ tham số `draft()` — không từ LLM args — và xâu result vào messages trước lượt cuối). `shop_id` gửi tới handler ≠ bất kỳ giá trị nào trong tool args (test tiêm args mang `shop_id` giả ⇒ bị bỏ, handler vẫn nhận shop_id thật). Cap vòng lặp chặn loop vô hạn (test: model gọi tool mãi ⇒ raise sau N vòng, KHÔNG treo). `pytest tests/test_drafter_tools.py` xanh.
APPROACH: Mở rộng `agent/drafter.py` (KHÔNG file mới): `LLMDrafter(llm, session_factory, tools=[...])` — inject `list[Tool]` (DI, như `build_router`), test tiêm fake tool. Loop: `step(tools=grounding+emit_reply)` → nếu tool_call ∈ grounding: `TOOLS[name].handler(user_id, shop_id=<draft arg>, args)`, append tool-result message, lặp; nếu `emit_reply`: kết. Cap `MAX_TOOL_ROUNDS` (đề xuất 4) — vượt ⇒ raise, không trả draft rỗng/bịa. `shop_id` baked từ tham số, args chỉ field trong `parameters`.
ALLOWED_FILES: agent/drafter.py, tests/test_drafter_tools.py, tests/test_drafter_live.py, docs/tasks/13-Task-OhanaAISeller-Drafter.md, docs/smokes/, docs/reviews/
GATE: .venv/bin/python -m pytest tests/test_drafter_tools.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools api auth && .venv/bin/ruff check . --no-cache
RETRY: 0/3
RISK: high (grounding sai vẫn là fact sai tới khách qua auto_send; và dispatch tool với `shop_id` sai = cross-tenant fact leak. Roadmap §8 "Fact hallucination"/"Multi-tenant data leak" = HIGH. TDD RED-first + per-step confirm.)
BLOCKED_BY: D0
SMOKE: PASS ref=docs/smokes/13-D1.md
REVIEW: PASS ref=docs/reviews/13-D1-auto-verdict.json human=docs/reviews/13-D1-human.md
<!-- /ADP -->

1. Test (**RED first**, RISK:high): `tests/test_drafter_tools.py` — `FakeLLMClient` kịch bản: lượt 1 phát `lookup_size` tool_call (args kèm `shop_id` giả), lượt 2 phát `emit_reply`. Assert: (a) handler nhận `shop_id` thật (draft arg), không phải giá trị giả trong args; (b) tool result xâu vào messages lượt 2; (c) draft cuối phản ánh result; (d) cap: model gọi tool vô hạn ⇒ raise sau `MAX_TOOL_ROUNDS`. Confirm ĐỎ.
2. Mở rộng `LLMDrafter`: nhận `tools`, dựng tool schema list + `emit_reply`, tool-dispatch loop với cap.
3. Live-smoke `tests/test_drafter_live.py -m live` case grounding (chạy lúc DONE).
4. **STOP+WAIT** cho checkpoint.

---

## §12 — Ghi chú để không trôi

- **Mount `api/webhook.py`** = `GD0-ZALO` (external, PRE-004 Tân). Spec này KHÔNG mount; giao Drafter + wiring factory trong `app/main.py` để lại cho `GD0-ZALO` khi creds về (tránh chạm `api/webhook.py`/`app/main.py` RISK_PATH khi chưa cần).
- **`emit_reply` intent enum** ở D0 là tập tối thiểu (5 mã). `GD0-INTENT` mở rộng thành 15 loại + escalation — enum sẽ đổi ở đó, KHÔNG ở đây.
- **Cap token**: persona 2000 + history 4000 (ISSUE-022/023, chưa đo tokenizer thật). Drafter thêm `emit_reply` schema + tool schema vào ngân sách — khi `GD0-OBS` đo token thật, kiểm lại tổng.
- **ISSUE-024 (Protocol lệch)**: `webhook.py` import `Drafter` thẳng từ orchestrator — `LLMDrafter` phải khớp Protocol đó (mypy structural). Đừng khai lại Protocol trong `drafter.py`.
