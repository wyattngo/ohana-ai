#!/bin/bash
# ============================================================
# ONFA Stop Reminder — Stop event hook
# Khi Claude Code kết thúc turn, inject reminder về
# STOP+WAIT rule và spec update requirement
# ============================================================

set -eo pipefail

INPUT=$(cat)
STOP_REASON=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('stop_reason',''))" 2>/dev/null || echo "")

# Only remind on end_turn (not on tool_use or max_tokens)
if [ "$STOP_REASON" != "end_turn" ]; then
    echo '{"continue": true}'
    exit 0
fi

echo '{"continue": true, "additionalContext": "STOP+WAIT RULE: Nếu vừa commit, DỪNG và chờ Wyatt review trước khi tiếp commit mới. Checklist: (1) Spec §13 Session log đã update? (2) Shipped/Pending table đã update? (3) Risk mới phát hiện đã ghi? (4) Wyatt đã sign off commit trước?"}'
exit 0
