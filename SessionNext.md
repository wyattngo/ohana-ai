# SessionNext — ADP PreCompact insurance

> Auto-written by checkpoint-on-compact.sh before compaction (trigger: manual).
> Resume from the SPEC BLOCK below + on-disk state — NOT from the compacted summary.

- ADP root: `/Users/wyattngo/Sites/localhost/ohana-ai`
- Active spec: `/Users/wyattngo/Sites/localhost/ohana-ai/docs/tasks/07-Task-OhanaAISeller-GeneralChat.md`  ·  phase: G0
- exec-state task_id: none
- Re-entry: re-run the phase GATE to re-verify green BEFORE writing more code (DONE ≠ self-report).

## Active phase block (verbatim)
```
SPEC_FILE: /Users/wyattngo/Sites/localhost/ohana-ai/docs/tasks/07-Task-OhanaAISeller-GeneralChat.md
<!-- ADP:PHASE G0 -->
STATUS: IN_PROGRESS
GOAL: `TogetherClient` implement `LLMClient`, trỏ Together base_url, model + key từ `Settings`; `OpenAIClient` hết coupling module-level `alert_service` (hành vi 429 KHÔNG đổi); `tests/test_config.py` xfail cập nhật cho khớp thực tế mới.
APPROACH: `OpenAIClient.__init__` nhận `on_rate_limit: Callable[[], Awaitable[None]] | None = None`; `_create` gọi hook nếu có rồi **re-raise nguyên** (không nuốt, không retry — giữ y hệt hành vi cũ). Bỏ `from app import alert_service` + `type: ignore` kèm nó (F2 thêm ignore đó, giờ thành thừa). `TogetherClient(OpenAIClient)` đặt `base_url="https://api.together.xyz/v1"` + `api_key=settings.together_api_key` + `model=settings.together_model`. `app/config.py` += 2 field. **KHÔNG port `alert_service`** — ISSUE-010 vẫn OPEN cho phần alerting.
ALLOWED_FILES: agent/providers/openai_client.py, agent/providers/together_client.py, app/config.py, tests/test_together_client.py, tests/test_config.py, docs/reviews/, docs/tasks/07-Task-OhanaAISeller-GeneralChat.md
GATE: .venv/bin/python -m pytest tests/test_together_client.py tests/test_config.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools && .venv/bin/ruff check . && .venv/bin/ruff format --check .
RETRY: 0/3
RISK: medium (proposed — `agent/providers/` KHÔNG trong RISK_PATHS, nhưng đây là provider mới + đụng client 380 dòng; Wyatt ký)
BLOCKED_BY: (đã gỡ) PRE-G01 ✅ key hợp lệ · PRE-G03 ✅
<!-- /ADP -->
```
