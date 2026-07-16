#!/bin/bash
# ============================================================
# ONFA Staleness Detector — PostToolUse for Write/Edit
# Detect khi code changes conflict với CLAUDE.md hoặc skills
# ============================================================

set -eo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd','.'))" 2>/dev/null || echo ".")

if [ -z "$FILE_PATH" ]; then
    echo '{"continue": true}'
    exit 0
fi

ALERTS=""

# ----------------------------------------------------------
# CHECK 1: constants.php changed → CLAUDE.md may reference old ASSET_VERSION
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "config/constants\.php"; then
    ALERTS="${ALERTS}STALENESS: constants.php changed. Kiểm tra CLAUDE.md 'Final notes' section có reference đúng ASSET_VERSION hiện tại không. "
fi

# ----------------------------------------------------------
# CHECK 2: routes.php changed → skill page-recipes may be outdated
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "config/routes\.php"; then
    ALERTS="${ALERTS}STALENESS: routes.php changed. Kiểm tra .claude/skills/onfa-finapp-ui/references/onfa-page-recipes.md có cover route mới không. "
fi

# ----------------------------------------------------------
# CHECK 3: New controller created → CLAUDE.md 'Project layout' count outdated
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "controllers/[A-Z].*\.php$"; then
    # Check if this is a NEW file (not edit)
    TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
    if [ "$TOOL_NAME" = "Write" ]; then
        ALERTS="${ALERTS}STALENESS: New controller created. CLAUDE.md says '44 files' in controllers/ — update count. Also update 'Quick reference' table if new module. "
    fi
fi

# ----------------------------------------------------------
# CHECK 4: New library created → CLAUDE.md count outdated
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "libraries/[A-Z].*\.php$"; then
    TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
    if [ "$TOOL_NAME" = "Write" ]; then
        ALERTS="${ALERTS}STALENESS: New library created. CLAUDE.md says '43 files' in libraries/ — update count. "
    fi
fi

# ----------------------------------------------------------
# CHECK 5: New wiho_ table referenced → skill DB tables may need update
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "\.php$"; then
    if [ -f "$FILE_PATH" ]; then
        NEW_TABLES=$(grep -oE "wiho_[a-z_]+" "$FILE_PATH" 2>/dev/null | sort -u | while read tbl; do
            # Check if table is documented in skill reference
            if ! grep -q "$tbl" "$CWD/.claude/skills/onfa-finapp-ui/references/onfa-database-tables.md" 2>/dev/null; then
                echo "$tbl"
            fi
        done || true)
        if [ -n "$NEW_TABLES" ]; then
            ALERTS="${ALERTS}STALENESS: Undocumented wiho_ tables used: $(echo $NEW_TABLES | tr '\n' ', '). Update .claude/skills/onfa-finapp-ui/references/onfa-database-tables.md. "
        fi
    fi
fi

# ----------------------------------------------------------
# CHECK 6: Language files changed → skill i18n reference may need update
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "language/.*/_.+\.php$"; then
    ALERTS="${ALERTS}STALENESS: Language file changed. Kiểm tra .claude/skills/onfa-finapp-ui/references/i18n-and-helpers.md có cover keys mới không. "
fi

# ----------------------------------------------------------
# OUTPUT
# ----------------------------------------------------------
if [ -n "$ALERTS" ]; then
    ESCAPED=$(echo "$ALERTS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
    echo "{\"continue\": true, \"additionalContext\": ${ESCAPED}}"
    exit 0
fi

echo '{"continue": true}'
exit 0
