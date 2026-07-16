#!/bin/bash
# ============================================================
# ADP v2 P3 — SubagentStop gate-verdict (SHADOW / advisory)
# Khi một subagent dừng: chạy acceptance_cmd của micro-task (từ exec-state mà MAIN
# đã ghi TRƯỚC spawn, fix #2/#3); verdict = exit code, BIND vào adp_task_diff_sha
# (scope = files khai báo, FIX C). Guards: diff ⊆ files; no-op-diff → FAIL (fix #5,
# đóng #57719); agent-mismatch (exec-state.current_agent ≠ SubagentStop.agent_type).
# FIX E: ghi gate-verdict.json (snapshot cache cho progress-guard P4) + adp_audit_event
# (.adp-audit.jsonl = source-of-truth append-only).
# SHADOW: chỉ quan sát + log; LUÔN {"continue": true} + exit 0 (hard-block = P8).
# FIX F: test qua run.sh simulate stdin (không cần live SubagentStop).
# Failure-safe: mọi lỗi parse → continue true.
# Formats: docs/tasks/19-Task-ADP-v2-MultiAgent-Pipeline.md §P3
# ============================================================
set -o pipefail

_ADPHD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$_ADPHD/adp-lib.sh"
[ -f "$LIB" ] || { echo '{"continue": true}'; exit 0; }
# shellcheck source=adp-lib.sh
source "$LIB"

shadow_out() { echo '{"continue": true}'; exit 0; }   # early-exit passthrough (non-git/no-state)

# P8: recorder stays continue:true (the breaker progress-guard is the exit-2 enforcer);
# surface the verdict + phase-bridge nudge to main via additionalContext.
active_out() {
    python3 - "${1:-}" <<'PY' 2>/dev/null || echo '{"continue": true}'
import json, sys
msg = sys.argv[1] if len(sys.argv) > 1 else ""
print(json.dumps({"continue": True, "additionalContext": msg} if msg else {"continue": True}))
PY
    exit 0
}

INPUT=$(cat)
PYJSON="import sys,json; d=json.load(sys.stdin); print(d.get"
CWD=$(printf '%s' "$INPUT" | python3 -c "${PYJSON}('cwd','.'))" 2>/dev/null || echo ".")
AGENT_TYPE=$(printf '%s' "$INPUT" | python3 -c "${PYJSON}('agent_type',''))" 2>/dev/null || echo "")

# Gate only applies inside a git project repo (FIX H) that has a main-written
# exec-state for the just-finished task. Otherwise nothing to verdict.
adp_assert_git_repo "$CWD" || shadow_out
STATE=$(adp_exec_state_path "$CWD")
[ -f "$STATE" ] || shadow_out

TASK_ID=$(adp_exec_state_get "$CWD" task_id)
CUR_AGENT=$(adp_exec_state_get "$CWD" current_agent)
ACC=$(adp_exec_state_get "$CWD" acceptance_cmd)
RISK=$(adp_exec_state_get "$CWD" risk_tier)
PHASE=$(adp_exec_state_get "$CWD" parent_phase)
FILES_CSV=$(python3 - "$STATE" <<'PY' 2>/dev/null || true
import sys, json
try:
    print(",".join(json.load(open(sys.argv[1])).get("files", [])))
except Exception:
    pass
PY
)
[ -n "$ACC" ] || shadow_out          # no acceptance_cmd → cannot gate
IFS=',' read -r -a FILES_ARR <<< "$FILES_CSV"

# 1) run the task's acceptance test → exit code is the raw verdict signal
ACC_OUT=$(cd "$CWD" && bash -c "$ACC" 2>&1); ACC_RC=$?
# 2) per-task diff sha (scope = declared files; empty = no-op-diff)
TASK_SHA=$(adp_task_diff_sha "$CWD" "${FILES_ARR[@]}")
# 3) scope guard: every changed file must be declared
OOS=$(adp_task_diff_in_scope "$CWD" "$FILES_CSV"); SCOPE_RC=$?

# 4) verdict + flags (machine-derived; reviewer/agent NEVER ticks this)
VERDICT="PASS"; FLAGS=""
[ "$ACC_RC" -eq 0 ]    || { VERDICT="FAIL"; FLAGS="$FLAGS test-exit:$ACC_RC"; }
[ -n "$TASK_SHA" ]     || { VERDICT="FAIL"; FLAGS="$FLAGS no-op-diff"; }
[ "$SCOPE_RC" -eq 0 ]  || { VERDICT="FAIL"; FLAGS="$FLAGS out-of-scope:$OOS"; }
if [ -n "$CUR_AGENT" ] && [ -n "$AGENT_TYPE" ] && [ "$CUR_AGENT" != "$AGENT_TYPE" ]; then
    FLAGS="$FLAGS agent-mismatch:$AGENT_TYPE!=$CUR_AGENT"
fi

# 4b) RED-proof (P6, FIX #10): a GREEN is only trustworthy if the SAME acceptance_cmd
# was recorded RED (failing) BEFORE the code. No proof / green-before-code / cmd-swap →
# FAIL. This is the "ai test cái test" guard — a test never RED can't prove it binds to
# the diff (a no-op-or-always-green test would otherwise sail through).
RED_EXIT=$(adp_red_proof_get "$CWD" "$TASK_ID" red_exit)
RED_ACCSHA=$(adp_red_proof_get "$CWD" "$TASK_ID" acc_sha)
CUR_ACCSHA=$(adp_cmd_sha "$ACC")
if [ -z "$RED_EXIT" ]; then
    VERDICT="FAIL"; FLAGS="$FLAGS no-red-proof"
elif [ "$RED_EXIT" = "0" ]; then
    VERDICT="FAIL"; FLAGS="$FLAGS red-proof-bogus"
elif [ "$RED_ACCSHA" != "$CUR_ACCSHA" ]; then
    VERDICT="FAIL"; FLAGS="$FLAGS red-cmd-mismatch"
fi

FLAGS=$(printf '%s' "$FLAGS" | sed 's/^ *//')

# 5) FIX E: snapshot cache (single-writer = this hook) + source-of-truth audit
python3 - "$CWD/docs/.adp-gate-verdict.json" "$TASK_ID" "$VERDICT" "${TASK_SHA:-}" "$ACC_RC" "$FLAGS" <<'PY' 2>/dev/null || true
import sys, json, datetime
f, task_id, verdict, sha, rc, flags = sys.argv[1:7]
obj = {
    "ts": datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z"),
    "task_id": task_id, "verdict": verdict, "task_diff_sha": sha,
    "gate_exit": rc, "flags": flags, "mode": "active",
}
open(f, "w").write(json.dumps(obj, ensure_ascii=False) + "\n")
PY
adp_audit_event "$CWD" gate=gate-verdict mode=active outcome="$VERDICT" \
    task="$TASK_ID" agent="$CUR_AGENT" tier="$RISK" phase="$PHASE" \
    task_diff="${TASK_SHA:-}" gate_exit="$ACC_RC" flags="$FLAGS"

# 6) P8 — recorder + phase-bridge nudge (FIX B). gate-verdict stays continue:true; the
# breaker (progress-guard) is what exit-2 blocks the NEXT spawn on a repeated/financial
# FAIL trail. On the LAST micro-task PASS of a phase, main runs adp-checkpoint.sh in the
# project repo to make the ADP phase DONE (micro-PASS ≠ phase-DONE, §2.6).
if [ "$VERDICT" = "PASS" ]; then
    active_out "ADP micro-task PASS (task=$TASK_ID phase=$PHASE). phase-bridge: when ALL micro-tasks of this ADP:PHASE have PASSed, run adp-checkpoint.sh in the project repo to make the phase DONE."
else
    active_out "ADP GATE FAIL (task=$TASK_ID flags=[$FLAGS]). Do NOT treat this micro-task as done; the breaker will REFUSE the next spawn on a repeated/financial FAIL."
fi
