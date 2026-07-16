#!/bin/bash
# ============================================================
# ONFA Pre-Commit Hygiene — Pattern I enforcement
# Chạy trước mỗi git commit, BLOCK nếu phát hiện lỗi
# Dựa trên bài học: SITE_PATH leak, ASSET_VERSION rollback,
# config staged, raw SQL concat
# ============================================================

set -eo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd','.'))" 2>/dev/null || echo ".")

cd "$CWD" 2>/dev/null || cd .

ERRORS=""
WARNINGS=""

# ----------------------------------------------------------
# CHECK 1: ASSET_VERSION not rolled back
# Compare staged constants.php with HEAD
# ----------------------------------------------------------
if git diff --cached --name-only 2>/dev/null | grep -q "config/constants.php"; then
    OLD_VER=$(git show HEAD:application/config/constants.php 2>/dev/null | grep -oP "ASSET_VERSION.*?(\d+)" | grep -oP '\d+$' || echo "0")
    NEW_VER=$(git diff --cached -p application/config/constants.php 2>/dev/null | grep "^+" | grep -oP "ASSET_VERSION.*?(\d+)" | grep -oP '\d+$' || echo "0")
    
    if [ -n "$OLD_VER" ] && [ -n "$NEW_VER" ] && [ "$NEW_VER" -lt "$OLD_VER" ] 2>/dev/null; then
        ERRORS="${ERRORS}ASSET_VERSION_ROLLBACK: Version giảm từ ${OLD_VER} xuống ${NEW_VER}. Phải bump lên, không được rollback.\n"
    fi
fi

# ----------------------------------------------------------
# CHECK 2: SITE_PATH leak (localhost, 127.0.0.1, local dev paths)
# ----------------------------------------------------------
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || echo "")
if [ -n "$STAGED_FILES" ]; then
    SITE_LEAK=$(git diff --cached -p 2>/dev/null | grep "^+" | grep -iE "localhost:81|127\.0\.0\.1:81|SITE_PATH.*localhost|SITE_URL.*localhost" | head -3 || true)
    if [ -n "$SITE_LEAK" ]; then
        ERRORS="${ERRORS}SITE_PATH_LEAK: localhost/dev URL found in staged changes. Sẽ break production. Fix trước khi commit.\n"
    fi
fi

# ----------------------------------------------------------
# CHECK 3: config.php or database.php staged (credentials)
# ----------------------------------------------------------
if echo "$STAGED_FILES" | grep -qE "config/config\.php|config/database\.php"; then
    ERRORS="${ERRORS}CONFIG_STAGED: config.php hoặc database.php đang staged — chứa credentials, KHÔNG commit. Unstage: git reset HEAD application/config/{config,database}.php\n"
fi

# ----------------------------------------------------------
# CHECK 4: Raw SQL concatenation in new code
# ----------------------------------------------------------
RAW_SQL=$(git diff --cached -p 2>/dev/null | grep "^+" | grep -E "WHERE.*=\s*['\"]?\s*\.\s*\\\$" | head -3 || true)
if [ -n "$RAW_SQL" ]; then
    WARNINGS="${WARNINGS}RAW_SQL_CONCAT: New code has raw SQL concatenation — SQL injection risk. Dùng CI3 query builder hoặc bindings.\n"
fi

# ----------------------------------------------------------
# CHECK 5: Hardcoded secrets pattern
# ----------------------------------------------------------
SECRET_LEAK=$(git diff --cached -p 2>/dev/null | grep "^+" | grep -iE "password\s*=\s*['\"][^'\"]{8,}|api_key\s*=\s*['\"]|secret\s*=\s*['\"][^'\"]{8,}" | grep -vE "getenv|DRNICK_|getMessage|example|placeholder|config\[" | head -3 || true)
if [ -n "$SECRET_LEAK" ]; then
    WARNINGS="${WARNINGS}POSSIBLE_SECRET: Hardcoded credential pattern detected in new code. Dùng getenv() + fallback per ONFA convention.\n"
fi

# ----------------------------------------------------------
# CHECK 6: CSS/JS changed but ASSET_VERSION not bumped
# ----------------------------------------------------------
if echo "$STAGED_FILES" | grep -qE "assets/css/|assets/js/|templates/script/"; then
    if ! echo "$STAGED_FILES" | grep -q "config/constants.php"; then
        WARNINGS="${WARNINGS}ASSET_VERSION_NOT_BUMPED: CSS/JS files changed but constants.php not staged. Users trên PWA sẽ thấy cached version. Bump ASSET_VERSION.\n"
    fi
fi

# ----------------------------------------------------------
# CHECK 7: V2 include path check (inc/wallet/ vs inc/walletV2/)
# ----------------------------------------------------------
WRONG_INCLUDE=$(git diff --cached -p 2>/dev/null | grep "^+" | grep -E "include.*inc/wallet/" | grep -vE "inc/walletV2/" | head -3 || true)
if echo "$STAGED_FILES" | grep -qE "walletV2" && [ -n "$WRONG_INCLUDE" ]; then
    ERRORS="${ERRORS}V2_INCLUDE_PATH: V2 file using inc/wallet/ instead of inc/walletV2/. STEP 7 over-rename bug — đã fix trong STEP 8, đừng reintroduce.\n"
fi

# ----------------------------------------------------------
# CHECK 8: ADP — STATUS: DONE thiếu EVIDENCE trong staged spec
# DONE chỉ hợp lệ qua adp-checkpoint.sh (nó tự ghi EVIDENCE).
# ----------------------------------------------------------
ADP_SPECS=$(echo "$STAGED_FILES" | grep -E "docs/tasks/.*\.md" || true)
if [ -n "$ADP_SPECS" ]; then
    for SPEC_F in $ADP_SPECS; do
        [ -f "$SPEC_F" ] || continue
        grep -q 'ADP:PHASE' "$SPEC_F" 2>/dev/null || continue
        BAD_PHASES=$(awk '
            /<!-- ADP:PHASE/ { phase=$0; inb=1; has_done=0; has_ev=0; next }
            inb && /STATUS:[ ]*DONE/ { has_done=1 }
            inb && /^EVIDENCE:/ { has_ev=1 }
            /<!-- \/ADP -->/ { if (inb && has_done && !has_ev) print phase; inb=0 }
        ' "$SPEC_F" 2>/dev/null | head -3)
        if [ -n "$BAD_PHASES" ]; then
            ERRORS="${ERRORS}ADP_DONE_NO_EVIDENCE: ${SPEC_F} có phase STATUS: DONE thiếu EVIDENCE — DONE chỉ hợp lệ qua bash .claude/tools/adp-checkpoint.sh. Phases: $(echo "$BAD_PHASES" | tr '\n' ' ')\n"
        fi
    done
fi

# ----------------------------------------------------------
# OUTPUT
# ----------------------------------------------------------
if [ -n "$ERRORS" ]; then
    echo -e "PRE-COMMIT BLOCKED:\n${ERRORS}${WARNINGS}" >&2
    exit 2
fi

if [ -n "$WARNINGS" ]; then
    ESCAPED=$(echo -e "$WARNINGS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
    echo "{\"continue\": true, \"additionalContext\": ${ESCAPED}}"
    exit 0
fi

echo '{"continue": true}'
exit 0
