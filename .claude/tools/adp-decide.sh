#!/bin/bash
# =============================================================================
# adp-decide.sh — 3-Option Decision Protocol CLI (Task #20 P3, ADP V2.3).
#
# The Decision Protocol formalizes "when a conflict/decision arises (setup or coding),
# present the 3 most viable options and let the human choose" into an auditable gate.
# A decision lives as an `adp-decision/v1` artifact (schema §3.1); this CLI validates,
# resolves, and detects open ones. The deterministic spine — NOT an LLM — owns the
# format invariants (exactly 3 options, exactly one recommended).
#
# Subcommands:
#   validate <file>            Echo OK/rc0 if conformant; else violation/rc1.
#   open     <repo>            Echo the pending file if an UNRESOLVED decision exists
#                              (chosen==null) under <repo>/docs; rc0 if open, rc1 if none.
#   resolve  <file> <A|B|C> <by>
#                              Validate → set chosen/decided_by/ts → append
#                              <repo>/docs/.adp-decisions.jsonl (append-only log) → rc0.
#                              Refuses an invalid artifact or a choice not in the options.
#
# Read-only except `resolve` (writes the artifact + the jsonl log). Exit: 0 ok · 2 usage · 1 invalid.
# =============================================================================
set -uo pipefail

_ADPTD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$_ADPTD/../hooks/adp-lib.sh"
[ -f "$LIB" ] || { echo "FATAL: adp-lib.sh not found" >&2; exit 2; }
source "$LIB"

cmd="${1:-}"; shift || true

case "$cmd" in
  validate)
    f="${1:-}"; [ -n "$f" ] || { echo "usage: adp-decide.sh validate <file>" >&2; exit 2; }
    out="$(adp_decision_validate "$f")"; rc=$?
    echo "$out"; exit $rc ;;

  open)
    repo="${1:-}"; [ -n "$repo" ] || { echo "usage: adp-decide.sh open <repo>" >&2; exit 2; }
    pend="$repo/docs/.adp-decision-pending.json"
    [ -f "$pend" ] || exit 1
    o="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("1" if d.get("chosen") in (None,"") else "0")' "$pend" 2>/dev/null)"
    [ "$o" = "1" ] && { echo "$pend"; exit 0; } || exit 1 ;;

  resolve)
    f="${1:-}"; choice="${2:-}"; by="${3:-}"
    [ -n "$f" ] && [ -n "$choice" ] && [ -n "$by" ] || { echo "usage: adp-decide.sh resolve <file> <A|B|C> <by>" >&2; exit 2; }
    adp_decision_validate "$f" >/dev/null || { echo "REFUSE: not a conformant adp-decision/v1: $f" >&2; exit 1; }
    log="$(cd "$(dirname "$f")" && pwd)/.adp-decisions.jsonl"
    python3 - "$f" "$choice" "$by" "$log" <<'PY' || { echo "REFUSE: resolve failed (choice not in options?)" >&2; exit 1; }
import json, sys, datetime, os, tempfile
f, choice, by, log = sys.argv[1:5]
d = json.load(open(f))
ids = [o.get("id") for o in d.get("options", [])]
if choice not in ids:
    sys.exit(1)
ts = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
d["chosen"] = choice; d["decided_by"] = by; d["ts"] = ts
# atomic write: temp in same dir + os.replace (no partial/corrupt artifact on crash)
dirn = os.path.dirname(os.path.abspath(f))
fd, tmp = tempfile.mkstemp(dir=dirn, suffix=".tmp")
with os.fdopen(fd, "w") as fh:
    json.dump(d, fh, ensure_ascii=False, indent=2); fh.write("\n")
os.replace(tmp, f)
rec = next((o["id"] for o in d["options"] if o.get("recommended") is True), None)
line = {"ts": ts, "id": d.get("id"), "trigger": d.get("trigger"),
        "chosen": choice, "recommended_was": rec, "decided_by": by,
        "context": d.get("context", "")[:200]}
with open(log, "a") as fh:
    fh.write(json.dumps(line, ensure_ascii=False) + "\n")
print("resolved:", d.get("id"), "chosen=" + choice, "(recommended_was=%s)" % rec)
PY
    exit 0 ;;

  *)
    echo "usage: adp-decide.sh {validate <file> | open <repo> | resolve <file> <A|B|C> <by>}" >&2
    exit 2 ;;
esac
