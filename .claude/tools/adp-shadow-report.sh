#!/bin/bash
# =============================================================================
# adp-shadow-report.sh — ADP v2 P7 shadow-calibration report.
# Reads the append-only audit log (.adp-audit.jsonl), pairs each micro-task's
# DETERMINISTIC spine verdict (gate=gate-verdict, outcome PASS|FAIL) with its LLM
# ADVISORY verdict (gate=review, outcome APPROVE|REJECT) by task_id, and computes
# the FIX G divergence metrics:
#   false-APPROVE = advisory APPROVE ∧ spine FAIL  (advisory blessed a spine-fail —
#                   the dangerous direction: promoting the advisory to authority would
#                   have shipped a spine failure; spine EARNS its keep here)
#   false-REJECT  = advisory REJECT  ∧ spine PASS  (advisory too strict; spine lenient)
#
# Honesty (baked, non-negotiable): small N only catches GROSS divergence. This is NOT a
# ≈0% certification. Money-code needs a CONTINUOUS rolling monitor, never a one-shot gate.
#
# Usage: adp-shadow-report.sh [audit_log]
#   default audit_log = <workspace-root>/docs/.adp-audit.jsonl
# Prints a human report incl. the machine marker [N>=5] / [N<5] and VERDICT: GO|NO-GO.
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIT="${1:-$ROOT/docs/.adp-audit.jsonl}"

if [ ! -f "$AUDIT" ]; then
    echo "ADP P7 — Shadow Calibration Report"
    echo "audit: $AUDIT (NOT FOUND)"
    echo "N (spine-judged tasks): 0  [N<5]"
    echo "VERDICT: NO-GO (no calibration data)"
    echo "CAVEAT: small-N only catches gross divergence; not a certification."
    exit 0
fi

python3 - "$AUDIT" <<'PY'
import sys, json

audit = sys.argv[1]
spine = {}     # task_id -> last spine outcome (PASS|FAIL)
adv = {}       # task_id -> last advisory outcome (APPROVE|REJECT)
prov = {}      # task_id -> producer provenance (if logged)

with open(audit) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except Exception:
            continue
        gate = e.get("gate", "")
        task = e.get("task", "")
        out = (e.get("outcome", "") or "").upper()
        if not task:
            continue
        if gate == "gate-verdict" and out in ("PASS", "FAIL"):
            spine[task] = out
        elif gate == "review" and out in ("APPROVE", "REJECT", "NEEDS_REVIEW"):
            adv[task] = out
        if e.get("producer"):
            prov[task] = e["producer"]

n = len(spine)                         # calibration size = tasks the spine judged
paired = sorted(set(spine) & set(adv))
agree = false_approve = false_reject = other = 0
rows = []
for t in paired:
    s, a = spine[t], adv[t]
    if a == "APPROVE" and s == "FAIL":
        cls = "false-APPROVE"; false_approve += 1
    elif a == "REJECT" and s == "PASS":
        cls = "false-REJECT"; false_reject += 1
    elif (a == "APPROVE" and s == "PASS") or (a == "REJECT" and s == "FAIL"):
        cls = "agree"; agree += 1
    else:
        cls = "other(%s/%s)" % (a, s); other += 1
    rows.append((t, s, a, prov.get(t, "?"), cls))

marker = "[N>=5]" if n >= 5 else "[N<5]"
# GO logic: promotion to hard-block (P8) is only safe when the spine never FAILs work the
# advisory approved (false-APPROVE) AND there is enough data (N>=5).
go = (n >= 5 and false_approve == 0)
verdict = "GO" if go else "NO-GO"

print("ADP P7 — Shadow Calibration Report")
print("audit:", audit)
print("N (spine-judged tasks): %d  %s" % (n, marker))
print("paired (advisory+spine): %d" % len(paired))
print("  agree: %d" % agree)
print("  false-APPROVE: %d   (advisory APPROVE ∧ spine FAIL — spine caught it)" % false_approve)
print("  false-REJECT: %d   (advisory REJECT  ∧ spine PASS — advisory over-strict)" % false_reject)
if other:
    print("  other:         %d" % other)
print("--- per-task ---")
for t, s, a, p, cls in rows:
    print("  %-10s spine=%-4s advisory=%-7s producer=%-8s -> %s" % (t, s, a, p, cls))
# tasks with a spine verdict but no advisory (unpaired) — disclose, don't hide
unpaired = sorted(set(spine) - set(adv))
if unpaired:
    print("  (unpaired spine-only: %s)" % ", ".join(unpaired))
print("VERDICT: %s" % verdict)
if not go and n >= 5 and false_approve > 0:
    print("  reason: false-APPROVE>0 — investigate whether spine is over-strict or advisory"
          " over-lenient BEFORE promoting spine to hard-block (P8).")
elif n < 5:
    print("  reason: need >=5 spine-judged tasks for even a gross-fail read.")
print("CAVEAT: N=%d is a GROSS-FAIL smoke test, NOT a ≈0%% certification. The spine stays"
      " authority; money-code requires a CONTINUOUS rolling monitor, not this one-shot gate." % n)
PY
