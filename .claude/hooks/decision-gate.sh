#!/bin/bash
# =============================================================================
# decision-gate.sh — Stop hook: block end-of-turn while an OPEN decision exists.
# Task #20 P3 (ADP V2.3). The runtime half of the 3-Option Decision Protocol.
#
# An "open decision" = <cwd>/docs/.adp-decision-pending.json with chosen==null. While
# one is open the loop must STOP and wait for the human to pick (set "chosen"), exactly
# like the checkpoint REVIEW gate. The artifact's 3-option format is enforced by
# adp-decide.sh / adp_decision_validate; this hook only checks open-vs-resolved.
#
# MODE — SHADOW by default (P3): logs "would-block" + ALWAYS {"continue": true}. Promote
#   to hard-block (exit 2) in P6 after calibration, set ADP_DECISION_ACTIVE=1.
#   Escape hatch ADP_FORCE_SHADOW=1 always reverts to continue. Failure-safe: any parse
#   error / no cwd / no pending file → continue.
# =============================================================================
set -uo pipefail

_ADPHD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$_ADPHD/adp-lib.sh"
cont(){ echo '{"continue": true}'; exit 0; }
[ -f "$LIB" ] || cont
source "$LIB" 2>/dev/null || cont

RAW="$(cat 2>/dev/null)"; [ -n "$RAW" ] || cont
CWD="$(printf '%s' "$RAW" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null)"
[ -n "$CWD" ] || cont
PEND="$CWD/docs/.adp-decision-pending.json"
[ -f "$PEND" ] || cont

OPEN="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("1" if d.get("chosen") in (None,"") else "0")' "$PEND" 2>/dev/null)"
[ "$OPEN" = "1" ] || cont   # resolved → nothing to gate

# There IS an open decision.
DID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("id",""))' "$PEND" 2>/dev/null)"
if declare -f adp_audit_event >/dev/null 2>&1; then
  adp_audit_event "$CWD" decision-gate '{"decision":"would-block","reason":"open-decision","id":"'"$DID"'"}' 2>/dev/null || true
fi

if [ "${ADP_DECISION_ACTIVE:-0}" = "1" ] && [ "${ADP_FORCE_SHADOW:-0}" != "1" ]; then
  # P6 hard-block path (inert until promoted).
  echo "ADP decision-gate: open decision '$DID' at $PEND — pick an option (set \"chosen\": A|B|C via adp-decide.sh resolve) before ending the turn." >&2
  echo '{"continue": false, "stopReason": "ADP open decision — resolve before continuing."}'
  exit 2
fi

# SHADOW (default): observe only.
echo '{"continue": true}'
exit 0
