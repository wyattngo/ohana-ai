# ADP v2 — Hook Contract (FROZEN, E5)

- **Status:** FROZEN 2026-06-18 (ADP v2 spec #19 P5)
- **Pinned to:** Claude Code CLI **2.1.158** / Cowork (Cowork DOES fire `settings.json` hooks)
- **Evidence (source of truth):** `docs/reviews/pf3-hook-probe-2026-06-18.jsonl` (throwaway probe, verified-by-execution per ADR-adp-v2 PF3)
- **Change-control:** This contract is consumed by `gate-verdict.sh` (P3), `progress-guard.sh` (P4), `checkpoint-on-compact.sh` (P5). **If the CC version changes, RE-RUN the probe and DIFF this contract BEFORE promoting any hook from SHADOW to hard-block (P8).** A silent field-rename upstream would make a hook a silent no-op (Risk #1) — the liveness canary (#9, progress-guard `--canary`) is the runtime backstop.

---

## 1. PreToolUse — subagent spawn  → `progress-guard.sh`
- **Event:** `PreToolUse`
- **`tool_name`:** `"Agent"` (NOT `"Task"`)
- **matcher (settings.json):** `"Agent"`
- **top-level keys:** `cwd`, `effort`, `hook_event_name`, `permission_mode`, `session_id`, `tool_input`, `tool_name`, `tool_use_id`, `transcript_path`
- **`tool_input` keys:** `description`, `prompt`, `subagent_type`
- **jq paths the hook reads:**
  - cwd → `.cwd`
  - which agent is about to spawn → `.tool_input.subagent_type`
- **Fires:** BEFORE the spawn. Main must have written `<cwd>/docs/.adp-exec-state.json` already (P2 pre-spawn ritual).

## 2. SubagentStop — subagent finished  → `gate-verdict.sh`
- **Event:** `SubagentStop`
- **`tool_name`:** `""` (empty)
- **matcher (settings.json):** none (all SubagentStop)
- **top-level keys:** `agent_id`, `agent_transcript_path`, `agent_type`, `background_tasks`, `cwd`, `hook_event_name`, `last_assistant_message`, `permission_mode`, `session_crons`, `session_id`, `stop_hook_active`, `transcript_path`
- **`tool_input`:** `null` (none)
- **jq paths the hook reads:**
  - cwd → `.cwd`
  - which agent finished (cross-check) → `.agent_type`
  - PRIMARY task identity → main-written `docs/.adp-exec-state.json` (`task_id`, `acceptance_cmd`, `files`), per fix #2/#3 (`agent_type` is only a cross-check, not the source of truth).

## 3. PreCompact — before compaction  → `checkpoint-on-compact.sh`
- **Event:** `PreCompact`
- **matcher (settings.json):** `"manual|auto"`
- **Expected keys (defensive):** `cwd`, `trigger` (`"manual"`|`"auto"`), `session_id`, `transcript_path`, `custom_instructions`
- **⚠️ NOT in the pf3 probe** — field names above are from CC docs, NOT execution-verified on this build. The hook reads `.cwd` + `.trigger` defensively (missing → safe defaults) and never blocks. **Verify by execution on next probe pass.**

---

## 4. Invariants (all 3 hooks)
- **SHADOW (current):** every hook ALWAYS emits `{"continue": true}` and exits 0. Hard-block (`exit 2`) is gated to P8 (after P7 calibration GO).
- **Failure-safe:** any parse error → `{"continue": true}`.
- **Single-writer:** `gate-verdict.sh` owns `.adp-gate-verdict.json`; `progress-guard.sh` owns `.adp-breaker.json`; `adp_audit_event` appends `.adp-audit.jsonl` (source-of-truth). Main owns `.adp-exec-state.json`.
- **Verdict authority = deterministic spine** (test exit code + diff-binding), never an agent / LLM.
