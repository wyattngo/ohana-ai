# Spec 12 — Wire provider-429 counter vào đường chat thật (ISSUE-010 nửa còn lại)

> `app/alert_service.record_provider_429()` đã land (commit 97b6d87) nhưng **chưa ai tiêm** nó
> làm hook `on_rate_limit`. Client chat duy nhất dựng ở `api/chat.py:get_llm_client()` với hook
> = mặc định `None` ⇒ 429 vẫn không được đếm ở đường thật. Phase này tiêm hook + chứng minh một
> `RateLimitError` làm bộ đếm tăng mà `RateLimitError` vẫn re-raise nguyên vẹn. Đóng ISSUE-010.

**Origin:** ISSUE-010 (nửa `alert_service`) · **Owner (R):** Tân · **Approver (A):** Wyatt
**ROADMAP:** GD0-OBS

## Context

Audit-first (2026-07-21) đã dựng module + chỉnh tracker; nửa còn lại là wiring:

- `agent/providers/openai_client.py` gọi `self._on_rate_limit()` trong khối `except RateLimitError`
  rồi **re-raise nguyên vẹn** (fire-and-forget). Hook mặc định `None`.
- `TogetherClient.__init__` **đã forward** `on_rate_limit` xuống `OpenAIClient` — nên KHÔNG cần
  sửa `agent/providers/`, chỉ cần truyền hook lúc dựng.
- Site dựng DUY NHẤT: `api/chat.py:get_llm_client()` — `_client_cache = TogetherClient()`.
- **KHÔNG bị PRE-004 chặn:** chat path đã chạy thật end-to-end từ spec 07; webhook mount/Drafter
  (thứ cần PRE-004) là chuyện khác. Sửa lại giả định "F2/F3 gated" trong ISSUE-010.

Out of scope: Redis-hoá bộ đếm (drnick bản Redis kéo theo `health_service`/`latency_service`/
poller = spec 34/36/40); reader/alerting poller; các counter khác (tool-error, cost-cap).

## Pre-flight (đã verify trên đĩa)

- [x] `app/alert_service.record_provider_429` tồn tại, chữ ký `() -> Awaitable[None]` — khớp hook.
- [x] `TogetherClient` forward `on_rate_limit` → không cần đụng `agent/providers/`.
- [x] `api/chat.py` ∈ RISK_PATHS (manifest) ⇒ floor RISK ≥ medium.
- [x] `GD0-OBS` tồn tại trong `docs/ROADMAP.md` §6.3.

## Phases

<!-- ADP:PHASE W0 -->
STATUS: TODO
ROADMAP: GD0-OBS
GOAL: `api/chat.py:get_llm_client()` dựng client với `on_rate_limit=alert_service.record_provider_429`; một `openai.RateLimitError` từ tầng client làm `provider_429_count()` tăng đúng 1 VÀ `RateLimitError` vẫn thoát ra nguyên vẹn (không bị hook che). Không tiêm ⇒ đếm 0.
APPROACH: Tiêm hook tại điểm dựng DUY NHẤT (`get_llm_client`), không ở module scope — giữ nguyên lý do dựng-lười (thiếu key chỉ chết `/api/chat`, không chết cả app). Test đường 429 ở TẦNG CLIENT bằng fake `AsyncOpenAI` ném `RateLimitError` (không cần key/mạng), cộng một test rằng `get_llm_client` truyền đúng hook (patch `TogetherClient`, bắt kwargs, reset `_client_cache`). Fail-open của bộ đếm đã có test riêng ở `test_alert_service.py` — KHÔNG lặp lại. KHÔNG đụng `agent/providers/` (TogetherClient đã forward).
ALLOWED_FILES: api/chat.py, tests/test_llm_429_wiring.py, docs/tasks/12-Task-OhanaAISeller-429TelemetryWiring.md, docs/smokes/, docs/reviews/
GATE: .venv/bin/python -m pytest tests/test_llm_429_wiring.py tests/test_alert_service.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: medium (Wyatt ký 2026-07-21. Floor: `api/chat.py` ∈ RISK_PATHS. Không high: telemetry fire-and-forget, re-raise `RateLimitError` nguyên vẹn, KHÔNG đổi hành vi gửi/tiền, KHÔNG chạm policy_gate/pending_reply.)
BLOCKED_BY: none (chat path chạy thật từ spec 07; KHÔNG chờ PRE-004)
SMOKE: N/A 429 provider không ép được on-demand để smoke đường thật; regression boot phủ bởi suite qua dependency_overrides, đường 429 phủ bởi fake RateLimitError ở test
<!-- /ADP -->

1. Test (**RED trước**): (a) fake `AsyncOpenAI.chat.completions.create` ném `openai.RateLimitError` → `OpenAIClient(on_rate_limit=record_provider_429).step(...)` phải re-raise `RateLimitError` VÀ `provider_429_count()==1`; (b) `get_llm_client()` (sau `_reset`) truyền `on_rate_limit is alert_service.record_provider_429` vào `TogetherClient`.
2. Wire: `api/chat.py:get_llm_client()` → `TogetherClient(on_rate_limit=alert_service.record_provider_429)` + import `from app import alert_service` **trong hàm** (giữ import module-level của client sạch — canh gác ISSUE-010).
3. **STOP+WAIT** cho checkpoint.

## Out of scope

Redis-hoá bộ đếm · alerting poller/reader · counter khác (tool-error/cost-cap/confirm-replay) ·
webhook-path 429 (webhook chưa mount, PRE-004). Mỗi thứ là spec riêng khi có nhu cầu thật.
