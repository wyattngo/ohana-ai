#!/bin/bash
# ============================================================
# ADP v2 P5 — PreCompact insurance (matcher manual|auto)
# Before context is compacted, snapshot the ACTIVE ADP phase block + exec-state into
# <root>/SessionNext.md so the next window resumes from the SPEC BLOCK (not from a
# lossy summary). Manual insurance per spec §"Platform locked". Never blocks.
# Failure-safe: any error → {"continue": true}.
# Fields (CC 2.1.158): PreCompact payload has cwd + trigger ("manual"|"auto").
#   PreCompact NOT in pf3 probe → field names treated defensively; re-verify on CC bump
#   (see docs/adr/hook-contract.md change-control).
# ============================================================
set -o pipefail

_ADPHD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$_ADPHD/adp-lib.sh"
[ -f "$LIB" ] || { echo '{"continue": true}'; exit 0; }
# shellcheck source=adp-lib.sh
source "$LIB"

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd','.'))" 2>/dev/null || echo ".")
TRIGGER=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('trigger',''))" 2>/dev/null || echo "")

ROOT=$(adp_find_root_or_scan "$CWD") || ROOT="$CWD"
SPEC_DIR=$(adp_manifest_get "$ROOT" SPEC_DIR); SPEC_DIR=${SPEC_DIR:-docs/tasks}
BLOCK=$(adp_active_block "$ROOT" "$SPEC_DIR") || BLOCK=""
SPEC_FILE=$(printf '%s\n' "$BLOCK" | adp_block_get SPEC_FILE)
PHASE_ID=$(printf '%s\n' "$BLOCK" | grep -m1 'ADP:PHASE' | sed 's/.*ADP:PHASE[ ]*//; s/[ ]*-->.*//')
STATE=$(adp_exec_state_path "$ROOT")
TASK_ID=$([ -f "$STATE" ] && adp_exec_state_get "$ROOT" task_id || echo "")

NEXT="$ROOT/SessionNext.md"
{
    echo "# SessionNext — ADP PreCompact insurance"
    echo
    echo "> Auto-written by checkpoint-on-compact.sh before compaction (trigger: ${TRIGGER:-?})."
    echo "> Resume from the SPEC BLOCK below + on-disk state — NOT from the compacted summary."
    echo
    echo "- ADP root: \`$ROOT\`"
    echo "- Active spec: \`${SPEC_FILE:-none}\`  ·  phase: ${PHASE_ID:-none}"
    echo "- exec-state task_id: ${TASK_ID:-none}"
    echo "- Re-entry: re-run the phase GATE to re-verify green BEFORE writing more code (DONE ≠ self-report)."
    echo
    if [ -n "$BLOCK" ]; then
        echo '## Active phase block (verbatim)'
        echo '```'
        printf '%s\n' "$BLOCK"
        echo '```'
    else
        echo "_No IN_PROGRESS ADP phase found at compaction time._"
    fi
} > "$NEXT" 2>/dev/null || true

echo '{"continue": true}'
exit 0
