#!/bin/bash
# ============================================================
# ONFA Pre-Bash Guard — PreToolUse hook for Bash commands
# Chặn dangerous commands + protect production paths
# ============================================================

set -eo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
    echo '{"continue": true}'
    exit 0
fi

# ----------------------------------------------------------
# RULE 1: Block destructive commands
# ----------------------------------------------------------
if echo "$COMMAND" | grep -qE "rm\s+-rf\s+/|rm\s+-rf\s+\.|dd\s+if=|mkfs|chmod\s+-R\s+777"; then
    echo "BLOCKED: Destructive command detected. Không chạy rm -rf trên root/cwd, dd, mkfs, hoặc chmod 777 recursive." >&2
    exit 2
fi

# ----------------------------------------------------------
# RULE 2: Block direct DB manipulation on production
# ----------------------------------------------------------
if echo "$COMMAND" | grep -qE "mysql.*onfa\.io|mysql.*-h\s+(onfa|prod)|DROP\s+TABLE|TRUNCATE\s+TABLE|DELETE\s+FROM\s+wiho_"; then
    echo "BLOCKED: Direct DB manipulation on production hoặc destructive SQL. Dùng migration file + rollback script thay vì raw SQL." >&2
    exit 2
fi

# ----------------------------------------------------------
# RULE 3: Block SSH/SCP to production without flag
# ----------------------------------------------------------
if echo "$COMMAND" | grep -qE "ssh.*onfa\.io|scp.*onfa\.io|rsync.*onfa\.io"; then
    echo "BLOCKED: Direct SSH/SCP/rsync to production. Deploy qua git workflow, không push trực tiếp." >&2
    exit 2
fi

# ----------------------------------------------------------
# RULE 4: Block npm/composer install (locked ONFA PHP/node stack)
#         Exception: npm install cho standalone drnickv4 node FE (web/, deps qua
#         web/package.json, node_modules gitignored — analog với pip 4b). composer
#         + npm ngoài drnickv4 vẫn khóa.
# ----------------------------------------------------------
if echo "$COMMAND" | grep -qE "npm\s+install"; then
    if echo "$COMMAND $CWD" | grep -q "drnickv4"; then
        echo '{"continue": true, "additionalContext": "npm install cho phép trong drnickv4 (node FE độc lập, deps qua web/package.json, node_modules gitignored). Không áp dụng cho ONFA PHP stack."}'
        exit 0
    fi
    echo "BLOCKED: ONFA stack is locked — không install dependencies mới (ngoài drnickv4 FE). Nếu thật sự cần, hỏi Wyatt trước." >&2
    exit 2
fi
if echo "$COMMAND" | grep -qE "composer\s+require|composer\s+install"; then
    echo "BLOCKED: ONFA PHP stack is locked — không composer install/require. Third-party code nằm trong third_party/ hoặc CDN trong footer.php. Nếu thật sự cần, hỏi Wyatt trước." >&2
    exit 2
fi

# ----------------------------------------------------------
# RULE 4b: pip install — allow for the standalone drnickv4 Python service
#          (riêng pyproject.toml, deps quản qua pip), block elsewhere
# ----------------------------------------------------------
if echo "$COMMAND" | grep -qE "pip\s+install"; then
    if echo "$COMMAND $CWD" | grep -q "drnickv4"; then
        echo '{"continue": true, "additionalContext": "pip install cho phép trong drnickv4 (Python service độc lập, deps quản qua pyproject.toml). Không áp dụng cho ONFA stack."}'
        exit 0
    fi
    echo "BLOCKED: ONFA stack is locked — không install dependencies mới (ngoài drnickv4). Nếu thật sự cần, hỏi Wyatt trước." >&2
    exit 2
fi

# ----------------------------------------------------------
# RULE 5: Warn on git push (not block, just context)
# ----------------------------------------------------------
if echo "$COMMAND" | grep -qE "git\s+push"; then
    echo '{"continue": true, "additionalContext": "REMINDER: Trước khi push, confirm: (1) branch đúng với spec, (2) ASSET_VERSION đã bump, (3) SITE_PATH không leak localhost, (4) test pass. STOP+WAIT rule: chờ Wyatt review sau push."}'
    exit 0
fi

# ----------------------------------------------------------
# RULE 6: Warn on git merge/rebase
# ----------------------------------------------------------
if echo "$COMMAND" | grep -qE "git\s+(merge|rebase)"; then
    echo '{"continue": true, "additionalContext": "WARNING: git merge/rebase có thể gây conflict trên shared files. Confirm với Wyatt trước khi merge vào main/master."}'
    exit 0
fi

# All clear
echo '{"continue": true}'
exit 0
