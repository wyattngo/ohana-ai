# ADR — ADP v2: Role-Specialized Multi-Agent Pipeline

- **Status:** ACCEPTED (2026-06-18, Wyatt)
- **Spec:** `docs/tasks/19-Task-ADP-v2-MultiAgent-Pipeline.md` v2.1
- **Supersedes:** #19 v1.0 framing · "ADP vNext Execution Pipeline" brief

## Context
ADP cần một exec/verify loop đa-agent chạy đường dài (sprint lớn) mà không để hallucination phá repo fintech. Failure mode cốt lõi (public incident `anthropics/claude-code#57719`: ~98 vòng, $313, net commit=1) = **verifier == doer**, agent tự khai DONE. Ba bản vẽ trước (#19 v1, vNext, v2.0) hoặc thiếu hook cụ thể, hoặc crown một LLM làm gatekeeper, hoặc dựng control-plane song song.

## Decision
1. **Trust-root = deterministic spine.** Quyền tick DONE thuộc về script/hook đọc **test exit code + diff-binding** (`adp_task_diff_sha`) + human-sign cho RISK:high. **LLM agents = advisor/producer, KHÔNG bao giờ authority** — kể cả test-reviewer (nó interpret, máy tick).
2. **Reuse > rebuild (anti-parallel-executor).** `coder.md` = **wrapper** invoke skill theo project (`ci3-code-generator`/`drnick-coder`/...), KHÔNG tự implement; `senior-engineer.md` → qua `onfa-spec-generator`. Agent net-new chỉ điều phối, không chứa logic implement/spec song song.
3. **Hai tầng DONE nối bằng phase-bridge.** micro-task PASS (gate-verdict hook, `.adp-audit.jsonl`) ≠ ADP phase DONE (`adp-checkpoint.sh` trong project repo). Mọi micro-PASS của 1 phase → checkpoint trong repo con mới = phase DONE.
4. **Shadow → calibrate → hard-block.** Advisory ≥5 task thật, đo `false-APPROVE := reviewer-advisory=APPROVE ∧ hook=FAIL` từ audit log, GO mới hard-block (P8, RISK:high, human-gate).
5. **§7 locked:** (a) suite-gated root + state/exec trong repo con có git · RISK P8=high/P3-6=medium/P0-2,P7=low · agents user-level + scope-guard + ONFA paths · model Sonnet baseline, Haiku medium advisory, Opus chỉ high.

## Consequences
**Tốt:** verdict authority tất định (hết "crown LLM"); reuse spine đã hardened (diff-binding P1, audit P2, RISK_PATHS, run.sh); breaker hard-5 no-re-arm + git-stash-on-trip; financial gate tất định; human gate vĩnh viễn money-code.

**Đánh đổi / rủi ro đã nhận diện:**
- **Phức tạp + chi phí** (5 agent + 3 hook + Sonnet/medium+). → tier theo RISK; MVP P0→P5 shadow trước.
- **Platform-lock fragility** (hook event/tool/field theo build CC, ship ~tuần). → PF3 verify-by-execution + **runtime breaker-liveness canary** (halt nếu breaker tự tắt âm thầm).
- **Per-task hash** đòi micro-task khai đúng `files`; guard `diff ⊆ files` chống out-of-scope leak.

## PF3 — RESOLVED by execution (2026-06-18, CLI 2.1.158 / Cowork)
Probe (`adp-hook-probe.sh`, throwaway) captured real hook payloads — both fired:
- **PreToolUse:** `tool_name="Agent"` (KHÔNG "Task"); `tool_input` = {description, prompt, **subagent_type**}; top_keys include cwd, effort, permission_mode, tool_use_id, transcript_path.
- **SubagentStop:** fires; top_keys = {**agent_type**, agent_id, agent_transcript_path, last_assistant_message, cwd, permission_mode, stop_hook_active, ...}; `tool_name=""`.
→ **Field map cho P3/P4 implement:** progress-guard matcher=`Agent`, đọc `.tool_input.subagent_type`; gate-verdict trên SubagentStop, `agent_type` available (dùng cross-check; primary = main-written state per fix #2/#3). Risk #1 (silent-no-op) verified-absent for this build. **Liveness canary (#9) vẫn bắt buộc** — verify này chỉ đúng cho build hiện tại; CC ship ~tuần.
