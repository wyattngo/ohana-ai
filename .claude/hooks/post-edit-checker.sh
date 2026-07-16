#!/bin/bash
# ============================================================
# ONFA Post-Edit Checker — PostToolUse hook for Write/Edit
# Kiểm tra code quality sau khi file được edit
# Không block (đã edit rồi), chỉ inject context/warnings
# ============================================================

set -eo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    echo '{"continue": true}'
    exit 0
fi

WARNINGS=""

# ----------------------------------------------------------
# CHECK 1: Raw SQL concatenation in PHP files
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "\.php$"; then
    if grep -nE "WHERE.*=\s*['\"]?\s*\.\s*\\\$" "$FILE_PATH" 2>/dev/null | head -3 | grep -q .; then
        RAW_SQL_LINES=$(grep -nE "WHERE.*=\s*['\"]?\s*\.\s*\\\$" "$FILE_PATH" 2>/dev/null | head -3 || true)
        WARNINGS="${WARNINGS}SQL_INJECTION_RISK: Raw SQL concatenation detected. Dùng query builder hoặc bindings. Lines: ${RAW_SQL_LINES}\n"
    fi
fi

# ----------------------------------------------------------
# CHECK 2: Hardcoded Vietnamese/English in view files (missing getMessage)
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "views/.*\.php$"; then
    # Check for bare text in span/button/h tags (not getMessage, not PHP var, not brand names)
    BARE_TEXT=$(grep -nE '<(span|button|h[1-6]|label|a\s)[^>]*>[A-Z][a-z]{3,}' "$FILE_PATH" 2>/dev/null \
        | grep -vE 'getMessage|ONFA|OFT|OHO|OHOP|MTT|USDT|OFC|Frogverse|ForwardX|Sky Breakers|Dr\.Nick|Sagaha' \
        | head -3 || true)
    if [ -n "$BARE_TEXT" ]; then
        WARNINGS="${WARNINGS}I18N_MISSING: Hardcoded text detected in view — dùng getMessage(). Lines: ${BARE_TEXT}\n"
    fi
fi

# ----------------------------------------------------------
# CHECK 3: Missing exit() after json_encode in controllers
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "controllers/.*\.php$"; then
    # Find json_encode lines not followed by exit within 2 lines
    MISSING_EXIT=$(python3 -c "
import sys
lines = open('$FILE_PATH', 'r', errors='ignore').readlines()
issues = []
for i, line in enumerate(lines):
    if 'json_encode' in line and 'echo' in line:
        # Check next 2 lines for exit
        found_exit = False
        for j in range(i+1, min(i+3, len(lines))):
            if 'exit' in lines[j]:
                found_exit = True
                break
        if not found_exit:
            issues.append(f'Line {i+1}')
if issues:
    print(', '.join(issues[:3]))
" 2>/dev/null)
    if [ -n "$MISSING_EXIT" ]; then
        WARNINGS="${WARNINGS}MISSING_EXIT: echo json_encode() without exit() detected. AJAX endpoint sẽ output thừa. ${MISSING_EXIT}\n"
    fi
fi

# ----------------------------------------------------------
# CHECK 4: Wrong brand colors
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "\.(php|css|js)$"; then
    WRONG_COLORS=$(grep -niE '#ffbf00|#C8D432|#f4c842|#FFD700|color:\s*gold|color:\s*yellow' "$FILE_PATH" 2>/dev/null | head -3 || true)
    if [ -n "$WRONG_COLORS" ]; then
        WARNINGS="${WARNINGS}WRONG_BRAND_COLOR: Sai brand color. ONFA dùng #e1b238 (primary gold), không dùng #ffbf00/#C8D432/#f4c842/#FFD700/gold/yellow. Lines: ${WRONG_COLORS}\n"
    fi
fi

# ----------------------------------------------------------
# CHECK 5: Bootstrap 4 data attributes (should be Bootstrap 5)
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "views/.*\.php$"; then
    BS4_ATTRS=$(grep -nE 'data-toggle=|data-target=|data-dismiss=' "$FILE_PATH" 2>/dev/null | grep -vE 'data-bs-' | head -3 || true)
    if [ -n "$BS4_ATTRS" ]; then
        WARNINGS="${WARNINGS}BOOTSTRAP_VERSION: Bootstrap 4 attributes detected. ONFA dùng Bootstrap 5: data-bs-toggle, data-bs-target, data-bs-dismiss. Lines: ${BS4_ATTRS}\n"
    fi
fi

# ----------------------------------------------------------
# CHECK 6: alert() or confirm() in JS (should use Lobibox)
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "\.(js|php)$"; then
    NATIVE_ALERT=$(grep -nE '\balert\s*\(|confirm\s*\(' "$FILE_PATH" 2>/dev/null | grep -vE '//|console\.|Lobibox|\*' | head -3 || true)
    if [ -n "$NATIVE_ALERT" ]; then
        WARNINGS="${WARNINGS}NATIVE_DIALOG: alert()/confirm() detected — dùng Lobibox thay vì native dialog. Lines: ${NATIVE_ALERT}\n"
    fi
fi

# ----------------------------------------------------------
# CHECK 7: Control-plane regression — sửa hook/tool/test thì chạy suite
# .claude/ KHÔNG thuộc git repo nào → pre-commit không gate được; bắt tại EDIT.
# ----------------------------------------------------------
if echo "$FILE_PATH" | grep -qE "\.claude/(hooks|tools|tests)/.*\.sh$"; then
    SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests" 2>/dev/null && pwd)/run.sh"
    if [ -x "$SUITE" ]; then
        if SUITE_OUT=$(bash "$SUITE" 2>&1); then
            RES=$(echo "$SUITE_OUT" | grep -E "^RESULT:" | head -1 || true)
            WARNINGS="${WARNINGS}CONTROL_PLANE_OK: regression suite xanh sau khi sửa $(basename "$FILE_PATH") — ${RES}\n"
        else
            FAILED=$(echo "$SUITE_OUT" | grep -E "FAIL|RESULT:" | head -6 | tr '\n' ' ' || true)
            WARNINGS="${WARNINGS}CONTROL_PLANE_REGRESSION: Sửa $(basename "$FILE_PATH") làm suite ĐỎ → ${FAILED} · chạy lại: bash .claude/tests/run.sh\n"
        fi
    fi
fi

# ----------------------------------------------------------
# OUTPUT
# ----------------------------------------------------------
if [ -n "$WARNINGS" ]; then
    # Escape for JSON
    ESCAPED=$(echo -e "$WARNINGS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
    echo "{\"continue\": true, \"additionalContext\": ${ESCAPED}}"
    exit 0
fi

echo '{"continue": true}'
exit 0
