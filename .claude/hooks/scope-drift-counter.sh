#!/bin/bash
# ============================================================
# ONFA Scope Drift Counter — PostToolUse hook for Write/Edit
# Đếm số file đã edit trong session. Khi vượt threshold,
# nhắc kiểm tra spec drift.
# ============================================================

set -eo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','unknown'))" 2>/dev/null || echo "unknown")
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd','.'))" 2>/dev/null || echo ".")

if [ -z "$FILE_PATH" ]; then
    echo '{"continue": true}'
    exit 0
fi

# State file per session
STATE_DIR="/tmp/onfa-hooks"
mkdir -p "$STATE_DIR"
STATE_FILE="${STATE_DIR}/drift-${SESSION_ID}.json"

# Initialize or read state
if [ -f "$STATE_FILE" ]; then
    EDIT_COUNT=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('edit_count',0))" 2>/dev/null || echo "0")
    LAST_NUDGE=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('last_nudge_at',0))" 2>/dev/null || echo "0")
else
    EDIT_COUNT=0
    LAST_NUDGE=0
fi

# Increment
EDIT_COUNT=$((EDIT_COUNT + 1))
CURRENT_TIME=$(date +%s)

# Thresholds: nudge at 8 edits, then every 5 edits after
NUDGE_THRESHOLD=8
NUDGE_INTERVAL=5
SHOULD_NUDGE=false

if [ "$EDIT_COUNT" -ge "$NUDGE_THRESHOLD" ]; then
    EDITS_SINCE_NUDGE=$((EDIT_COUNT - LAST_NUDGE))
    if [ "$LAST_NUDGE" -eq 0 ] || [ "$EDITS_SINCE_NUDGE" -ge "$NUDGE_INTERVAL" ]; then
        SHOULD_NUDGE=true
    fi
fi

# Save state
if [ "$SHOULD_NUDGE" = true ]; then
    python3 -c "import json; json.dump({'edit_count': $EDIT_COUNT, 'last_nudge_at': $EDIT_COUNT}, open('$STATE_FILE','w'))"
else
    python3 -c "import json; json.dump({'edit_count': $EDIT_COUNT, 'last_nudge_at': $LAST_NUDGE}, open('$STATE_FILE','w'))"
fi

# Output
if [ "$SHOULD_NUDGE" = true ]; then
    echo "{\"continue\": true, \"additionalContext\": \"SCOPE DRIFT CHECK: Đã edit ${EDIT_COUNT} files trong session này. Kiểm tra: (1) Tất cả edits có nằm trong scope spec không? (2) Có file nào edit ngoài In Scope list? (3) Có cần tách commit không? Nếu đang đi lạc, STOP và review lại spec.\"}"
    exit 0
fi

echo '{"continue": true}'
exit 0
