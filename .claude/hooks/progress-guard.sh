#!/bin/bash
# ============================================================
# ADP v2 P4/P8 — PreToolUse[Agent] breaker + financial gate + canary (P8: ACTIVE)
# Fires BEFORE a subagent spawn. Reads the main-written exec-state (task about to
# run) and the gate-verdict audit trail, then decides whether the spawn should be
# allowed. Mechanisms:
#   • Breaker hard-5, no-re-arm     — 5 consecutive FAIL (this phase) → trip.
#   • E3 idempotency                — same task_id, last 2 FAIL share diff → trip@2.
#   • Exactly 1 tech-lead rethink   — 3 consecutive FAIL → rethink (once), else trip.
#   • Financial STOP (deterministic)— task files ∩ RISK_PATHS ≠ ∅ → block (money-code).
#   • FIX D: trip → STOP + would-stash (NO hard-reset default). Real stash = P8.
#   • E9 canary 2-tier: (a) --canary logic self-check on the REAL FSM (regression),
#                       (b) heartbeat liveness (detect CC silently not calling hook).
# FIX E: single-writer snapshot `<repo>/docs/.adp-breaker.json` + adp_audit_event
#        (.adp-audit.jsonl source-of-truth). Verdict authority = spine, never an agent.
# P8 ACTIVE (promoted 2026-06-18, Wyatt human-gate, ref docs/reviews/19-phase-8-human.md):
#   DECISION=block → real hard exit 2 (PreToolUse refuses the spawn). Escape hatch
#   ADP_FORCE_SHADOW=1 → revert to {"continue": true}. INERT for normal work: non-git OR
#   no exec-state → continue (only an active ADP exec-loop can ever be blocked).
# FIX F: unit-tested via simulated PreToolUse stdin + seeded audit (no live spawn).
# Failure-safe: any parse error → continue true.
# Formats: docs/tasks/19-Task-ADP-v2-MultiAgent-Pipeline.md §P4
# ============================================================
set -o pipefail

_ADPHD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$_ADPHD/adp-lib.sh"
[ -f "$LIB" ] || { echo '{"continue": true}'; exit 0; }
# shellcheck source=adp-lib.sh
source "$LIB"

NOW="${ADP_NOW:-$(date +%s 2>/dev/null || echo 0)}"
MAX_FAILS=5
RETHINK_AT=3
HB_MAX_AGE="${ADP_HB_MAX_AGE:-3600}"   # heartbeat older than this while active ⇒ dead

# --- shared FSM (single source; used by live hook AND logic-canary, E9 adj-A) -----
FSM=$(mktemp 2>/dev/null) || FSM="/tmp/adp-fsm.$$.py"
cat > "$FSM" <<'PY'
import sys, json, datetime
audit, state_path, phase, task_id, fin, now, hb_write, max_fails, rethink_at = sys.argv[1:10]
fin = (fin == "1"); now = int(now); max_fails = int(max_fails); rethink_at = int(rethink_at)
try:    prev = json.load(open(state_path))
except Exception: prev = {}
already_tripped = bool(prev.get("tripped"))
rethinks_used = int(prev.get("rethinks_used", 0))
events = []
try:
    for line in open(audit):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        if e.get("gate") == "gate-verdict": events.append(e)
except Exception: pass
# trailing consecutive FAIL for this phase
consec = 0
for e in reversed([e for e in events if str(e.get("phase")) == str(phase)]):
    if e.get("outcome") == "FAIL": consec += 1
    else: break
# E3: last 2 FAIL events for this task share the same diff
tf = [e for e in events if e.get("task") == task_id and e.get("outcome") == "FAIL"]
same_diff = bool(len(tf) >= 2 and tf[-1].get("task_diff") and tf[-1].get("task_diff") == tf[-2].get("task_diff"))
decision, reason, would_stash, tripped = "allow", "ok", False, already_tripped
if already_tripped:
    decision, reason = "block", "tripped-no-rearm"
elif fin:
    decision, reason = "block", "financial-STOP"
elif same_diff:
    decision, reason, would_stash, tripped = "block", "idempotency-trip@2", True, True
elif consec >= max_fails:
    decision, reason, would_stash, tripped = "block", "breaker-hard-5", True, True
elif consec >= rethink_at:
    if rethinks_used < 1:
        decision, reason = "block", "rethink"; rethinks_used += 1
    else:
        decision, reason, would_stash, tripped = "block", "rethink-exhausted-trip", True, True
out = {
  "ts": datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z"),
  "phase": phase, "task_id": task_id, "decision": decision, "reason": reason,
  "consecutive_fails": consec, "same_diff_fail": same_diff, "tripped": tripped,
  "rethinks_used": rethinks_used, "would_stash": would_stash, "financial": fin,
  "heartbeat_epoch": now if hb_write == "1" else prev.get("heartbeat_epoch", now),
  "mode": "active",
}
try: open(state_path, "w").write(json.dumps(out, ensure_ascii=False) + "\n")
except Exception: pass
print("%s|%s|%d" % (decision, reason, consec))
PY
cleanup_fsm() { rm -f "$FSM" 2>/dev/null; }
trap cleanup_fsm EXIT

# ====================== CANARY MODE (E9 two-tier) ===========================
if [ "${1:-}" = "--canary" ]; then
    REPO="${2:-.}"
    # (a) LOGIC canary: run the REAL FSM on a synthetic 5-FAIL trail → must block/trip.
    CD=$(mktemp -d 2>/dev/null) || CD="/tmp/adp-canary.$$"; mkdir -p "$CD"
    : > "$CD/audit.jsonl"
    for i in 1 2 3 4 5; do
        printf '{"gate":"gate-verdict","phase":"C","task":"c.t","outcome":"FAIL","task_diff":"d%d"}\n' "$i" >> "$CD/audit.jsonl"
    done
    LOGIC=$(python3 "$FSM" "$CD/audit.jsonl" "$CD/state.json" "C" "c.t" 0 "$NOW" 0 "$MAX_FAILS" "$RETHINK_AT" 2>/dev/null)
    rm -rf "$CD" 2>/dev/null
    case "$LOGIC" in block\|breaker-hard-5*) LOGIC_ST="OK";; *) LOGIC_ST="FAIL";; esac
    # (b) LIVENESS: heartbeat freshness (CC silently not calling hook ⇒ stale).
    HB=$(adp_artifact_field "$REPO/docs/.adp-breaker.json" heartbeat_epoch)
    if [ -z "$HB" ]; then
        LIVE_ST="UNKNOWN"     # never fired yet — not dead, just no data
    else
        AGE=$(( NOW - HB ))
        [ "$AGE" -le "$HB_MAX_AGE" ] && LIVE_ST="OK" || LIVE_ST="STALE"
    fi
    echo "CANARY logic=$LOGIC_ST liveness=$LIVE_ST"
    [ "$LOGIC_ST" = "OK" ] && { [ "$LIVE_ST" != "STALE" ]; }
    exit $?
fi

# ====================== LIVE HOOK MODE (PreToolUse[Agent]) ===================
shadow_out() { # $1 = additionalContext message (optional)
    python3 - "${1:-}" <<'PY' 2>/dev/null || echo '{"continue": true}'
import json, sys
msg = sys.argv[1] if len(sys.argv) > 1 else ""
print(json.dumps({"continue": True, "additionalContext": msg} if msg else {"continue": True}))
PY
    exit 0
}

# P8: real PreToolUse block. Escape hatch ADP_FORCE_SHADOW=1 → revert to continue.
hard_block() { # $1 = reason detail
    if [ "${ADP_FORCE_SHADOW:-0}" = "1" ]; then
        shadow_out "ADP would-block (ADP_FORCE_SHADOW override) $1"
    fi
    echo "ADP HARD-BLOCK (P8): $1" >&2
    echo "  → spawn refused by the deterministic spine. Fix the cause, or override with ADP_FORCE_SHADOW=1." >&2
    exit 2
}

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd','.'))" 2>/dev/null || echo ".")
SUBAGENT=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print((json.load(sys.stdin).get('tool_input') or {}).get('subagent_type',''))" 2>/dev/null || echo "")

adp_assert_git_repo "$CWD" || shadow_out
STATE=$(adp_exec_state_path "$CWD")
[ -f "$STATE" ] || shadow_out "ADP would-block: no exec-state (main must write a valid adp-handoff/v1 BEFORE spawn)."

PHASE=$(adp_exec_state_get "$CWD" parent_phase)
TASK_ID=$(adp_exec_state_get "$CWD" task_id)
FILES_CSV=$(python3 - "$STATE" <<'PY' 2>/dev/null || true
import sys, json
try: print(",".join(json.load(open(sys.argv[1])).get("files", [])))
except Exception: pass
PY
)
RISK_CSV=$(python3 - "$(adp_profile_path "$CWD")" <<'PY' 2>/dev/null || true
import sys, json
try: print(",".join(json.load(open(sys.argv[1])).get("risk_paths", [])))
except Exception: pass
PY
)

# Financial gate (deterministic): task files ∩ RISK_PATHS.
# adp_allowed_risk_overlap is now case-insensitive at the source (task_f1f2063f) — it
# folds both sides internally, so CapCase money-files (Wallet.php) match lowercase
# RISK_PATHS (wallet). No local pre-fold needed; one canonical folding for all call-sites.
FIN=0
if [ -n "$FILES_CSV" ] && [ -n "$RISK_CSV" ]; then
    if adp_allowed_risk_overlap "$FILES_CSV" "$RISK_CSV" >/dev/null 2>&1; then FIN=1; fi
fi

AUDIT="$CWD/docs/.adp-audit.jsonl"
BSTATE="$CWD/docs/.adp-breaker.json"
RES=$(python3 "$FSM" "$AUDIT" "$BSTATE" "${PHASE:-?}" "${TASK_ID:-?}" "$FIN" "$NOW" 1 "$MAX_FAILS" "$RETHINK_AT" 2>/dev/null)
DECISION="${RES%%|*}"; REST="${RES#*|}"; REASON="${REST%%|*}"; CONSEC="${RES##*|}"

adp_audit_event "$CWD" gate=progress-guard mode=active decision="${DECISION:-allow}" \
    reason="${REASON:-ok}" task="${TASK_ID:-?}" phase="${PHASE:-?}" subagent="$SUBAGENT" \
    consec_fails="${CONSEC:-0}" financial="$FIN"

if [ "$DECISION" = "block" ]; then
    hard_block "reason=${REASON} phase=${PHASE} task=${TASK_ID} consec_fails=${CONSEC} (trip ⇒ STOP + git stash, NO hard-reset; financial ⇒ Wyatt human-gate)"
fi
shadow_out
