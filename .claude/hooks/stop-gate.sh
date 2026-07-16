#!/bin/bash
# ============================================================
# ADP Stop Gate — Stop event hook
# Khi có ADP phase IN_PROGRESS và session đã edit file:
# chạy GATE command thật. Gate đỏ → block turn (Verification Gap).
# RETRY >= 3/3 → cho stop kèm chỉ thị rollback (không block).
# Failure-safe: mọi lỗi parse → continue true.
# Formats: docs/guides/adp-protocol.md §3
# ============================================================

set -o pipefail

_ADPHD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$_ADPHD/adp-lib.sh"
if [ ! -f "$LIB" ]; then
    echo '{"continue": true}'
    exit 0
fi
# shellcheck source=adp-lib.sh
source "$LIB"

# FIX J (ADP v2 P5): in exec-loop mode the SubagentStop micro-gate (gate-verdict.sh)
# owns per-task gating; disable stop-gate phase-mode here to avoid double-run /
# conflicting verdict. ADP phase DONE still goes through adp-checkpoint.sh.
if [ "${ADP_EXEC_LOOP:-0}" = "1" ]; then
    echo '{"continue": true}'
    exit 0
fi

INPUT=$(cat)
PYJSON="import sys,json; d=json.load(sys.stdin); print(d.get"
STOP_REASON=$(echo "$INPUT" | python3 -c "${PYJSON}('stop_reason',''))" 2>/dev/null || echo "")
STOP_ACTIVE=$(echo "$INPUT" | python3 -c "${PYJSON}('stop_hook_active',False))" 2>/dev/null || echo "False")
CWD=$(echo "$INPUT" | python3 -c "${PYJSON}('cwd','.'))" 2>/dev/null || echo ".")
SESSION_ID=$(echo "$INPUT" | python3 -c "${PYJSON}('session_id','unknown'))" 2>/dev/null || echo "unknown")

# Only gate real end-of-turn; never re-block a continuation we already forced (loop guard)
if [ "$STOP_REASON" != "end_turn" ] || [ "$STOP_ACTIVE" = "True" ] || [ "$STOP_ACTIVE" = "true" ]; then
    echo '{"continue": true}'
    exit 0
fi

ADP_ROOT=$(adp_find_root_or_scan "$CWD") || { echo '{"continue": true}'; exit 0; }
SPEC_DIR=$(adp_manifest_get "$ADP_ROOT" SPEC_DIR)
SPEC_DIR=${SPEC_DIR:-docs/tasks}

FALLBACK=0
BLOCK=$(adp_active_block "$ADP_ROOT" "$SPEC_DIR") || BLOCK=""
if [ -z "$BLOCK" ]; then
    # Không còn IN_PROGRESS nhưng session có edit → kiểm phase DONE gần nhất.
    # Bịt lỗ hổng fake-done: tự tay sửa STATUS: DONE mà chưa từng chạy gate.
    BLOCK=$(adp_last_done_block "$ADP_ROOT" "$SPEC_DIR") || { echo '{"continue": true}'; exit 0; }
    FALLBACK=1
fi
GATE=$(echo "$BLOCK" | adp_block_get GATE)
[ -z "$GATE" ] && { echo '{"continue": true}'; exit 0; }

# Skip when this session edited nothing (conversational turn) — reuse drift counter state
STATE_FILE="/tmp/onfa-hooks/drift-${SESSION_ID}.json"
EDIT_COUNT=0
if [ -f "$STATE_FILE" ]; then
    EDIT_COUNT=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('edit_count',0))" 2>/dev/null || echo "0")
fi
if [ "$EDIT_COUNT" -eq 0 ] 2>/dev/null; then
    echo '{"continue": true}'
    exit 0
fi

RETRY=$(echo "$BLOCK" | adp_block_get RETRY)
RETRY=${RETRY:-0/3}
RETRY_USED=${RETRY%%/*}
SPEC_FILE=$(echo "$BLOCK" | adp_block_get SPEC_FILE)
PHASE_ID=$(echo "$BLOCK" | grep -m1 'ADP:PHASE' | sed 's/.*ADP:PHASE[ ]*//; s/[ ]*-->.*//')

OUT=$(cd "$ADP_ROOT" && bash -c "$GATE" 2>&1)
RC=$?

emit_json() {
    # $1 = decision ("block" | ""), $2 = message
    python3 - "$1" <<'PY' 2>/dev/null || echo '{"continue": true}'
import json, sys, os
decision = sys.argv[1]
msg = os.environ.get("ADP_MSG", "")
if decision == "block":
    print(json.dumps({"decision": "block", "reason": msg}))
else:
    print(json.dumps({"continue": True, "additionalContext": msg}))
PY
}

if [ $RC -eq 0 ]; then
    if [ $FALLBACK -eq 1 ]; then
        EVID=$(echo "$BLOCK" | adp_block_get EVIDENCE)
        if [ -z "$EVID" ]; then
            export ADP_MSG="ADP WARNING: phase ${PHASE_ID} STATUS: DONE nhưng THIẾU EVIDENCE — theo protocol, DONE-thiếu-EVIDENCE = chưa done. Gate hiện XANH nên code OK, chỉ thiếu giao dịch checkpoint. Chạy: bash $_ADPHD/../tools/adp-checkpoint.sh (con đường duy nhất để DONE hợp lệ)."
            emit_json ""
            exit 0
        fi
        echo '{"continue": true}'
        exit 0
    fi
    export ADP_MSG="ADP GATE PASS ✅ (phase ${PHASE_ID}, lệnh: ${GATE}). Đủ điều kiện CHECKPOINT — chạy: bash $_ADPHD/../tools/adp-checkpoint.sh -m '<concern>' (script tự chạy GATE_FULL + commit + STATUS DONE + EVIDENCE). KHÔNG tự tay sửa STATUS."
    emit_json ""
    exit 0
fi

TAIL=$(echo "$OUT" | tail -15)
if [ $FALLBACK -eq 1 ]; then
    export ADP_MSG="ADP FAKE-DONE/REGRESSION: phase ${PHASE_ID} đang STATUS: DONE nhưng gate ĐỎ với code hiện tại (exit ${RC}): ${TAIL} || Hai lựa chọn: (1) sửa code cho gate xanh lại, (2) revert STATUS về IN_PROGRESS trong ${SPEC_FILE} + báo Wyatt. KHÔNG được để DONE tồn tại cùng gate đỏ."
    emit_json "block"
    exit 0
fi
if [ "${RETRY_USED:-0}" -ge 3 ] 2>/dev/null; then
    export ADP_MSG="ADP GATE FAILED (exit ${RC}) và RETRY đã ${RETRY} — theo protocol: STOP, KHÔNG sửa tiếp. Rollback về checkpoint git gần nhất, ghi error report vào ${SPEC_FILE} (STATUS → BLOCKED), báo Wyatt. Output cuối: ${TAIL}"
    emit_json ""
    exit 0
fi

export ADP_MSG="ADP GATE FAILED (exit ${RC}, phase ${PHASE_ID}): ${TAIL} || Turn chưa được kết thúc. Tự sửa trong ALLOWED_FILES rồi chạy lại gate: ${GATE}. Tăng RETRY trong ${SPEC_FILE} (hiện ${RETRY}, max 3). KHÔNG đổi kiến trúc/viết lại test để lách gate. Quá 3 lần → STOP + rollback + báo Wyatt."
emit_json "block"
exit 0
