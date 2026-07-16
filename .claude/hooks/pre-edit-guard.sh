#!/bin/bash
# ============================================================
# ADP Pre-Edit Guard — PreToolUse hook for Write/Edit (generic, project-agnostic).
# Manifest-aware ALLOWED_FILES / RISK_PATHS tiered gating — the ADP-core rule only.
# Project-specific protected-path rules (dead-code dirs, shared layouts, vendored
# code, config secrets, global asset files) are intentionally NOT shipped here; add
# them per project on top of this guard if you want them (the source ONFA workspace
# keeps a hybrid version with those extra rules).
# Input:  JSON on stdin from Claude Code
# Output: JSON on stdout (exit 0) or stderr + exit 2 (block)
# ============================================================

set -eo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd','.'))" 2>/dev/null || echo ".")

if [ -z "$TOOL_NAME" ]; then
    echo '{"continue": true}'
    exit 0
fi

# Normalize to absolute path
case "$TOOL_NAME" in
    /*) : ;;
    *) TOOL_NAME="$CWD/$TOOL_NAME" ;;
esac

# ----------------------------------------------------------
# ADP tiered gating (manifest-aware)
# Đọc ADP:MANIFEST của project chứa file + ADP:PHASE block active.
# - Trong ALLOWED_FILES → pass. docs/* + CLAUDE.md luôn editable.
# - Ngoài ALLOWED_FILES + RISK_PATHS → HARD BLOCK.
# - Ngoài ALLOWED_FILES, non-risk → warn (scope drift).
# - Không có phase active + RISK_PATHS → warn (audit-first reminder).
# Failure-safe: không có manifest / lỗi parse → bỏ qua rule này.
# Formats: docs/guides/adp-protocol.md §3
# ----------------------------------------------------------
_ADPHD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADP_LIB="$_ADPHD/adp-lib.sh"
if [ -f "$ADP_LIB" ]; then
    # shellcheck source=adp-lib.sh
    source "$ADP_LIB"
    ADP_ROOT=$(adp_find_root "$(dirname "$TOOL_NAME")" 2>/dev/null) || ADP_ROOT=""
    if [ -n "$ADP_ROOT" ]; then
        REL="${TOOL_NAME#"$ADP_ROOT"/}"
        case "$REL" in
            docs/* | CLAUDE.md)
                : # spec/memory/docs luôn editable — agent phải update được STATUS
                ;;
            *)
                RISK_PATHS=$(adp_manifest_get "$ADP_ROOT" RISK_PATHS)
                SPEC_DIR=$(adp_manifest_get "$ADP_ROOT" SPEC_DIR)
                SPEC_DIR=${SPEC_DIR:-docs/tasks}
                IS_RISK=false
                if [ -n "$RISK_PATHS" ] && adp_path_match "$REL" "$RISK_PATHS" substr; then
                    IS_RISK=true
                fi
                ADP_BLOCK=$(adp_active_block "$ADP_ROOT" "$SPEC_DIR" 2>/dev/null) || ADP_BLOCK=""
                if [ -n "$ADP_BLOCK" ]; then
                    ALLOWED=$(echo "$ADP_BLOCK" | adp_block_get ALLOWED_FILES)
                    ADP_SPEC=$(echo "$ADP_BLOCK" | adp_block_get SPEC_FILE)
                    if [ -n "$ALLOWED" ] && adp_path_match "$REL" "$ALLOWED" exact; then
                        : # trong scope phase → pass, rơi xuống các rule sau
                    elif [ "$IS_RISK" = true ]; then
                        echo "ADP BLOCKED: '$REL' chạm RISK_PATHS và nằm NGOÀI ALLOWED_FILES của phase đang IN_PROGRESS (spec: ${ADP_SPEC}). Cần Wyatt approve: thêm file vào ALLOWED_FILES trong spec rồi edit lại. Ref: docs/guides/adp-protocol.md §4" >&2
                        exit 2
                    else
                        echo "{\"continue\": true, \"additionalContext\": \"ADP SCOPE DRIFT: '$REL' ngoài ALLOWED_FILES của phase IN_PROGRESS (spec: ${ADP_SPEC}). Nếu là task ngoài ADP do Wyatt yêu cầu trực tiếp → OK. Nếu đang chạy phase → STOP, quay về scope hoặc xin Wyatt thêm file vào ALLOWED_FILES.\"}"
                        exit 0
                    fi
                elif [ "$IS_RISK" = true ]; then
                    echo '{"continue": true, "additionalContext": "ADP RISK PATH (money/XP/funds): file thuộc RISK_PATHS. Quy tắc tiered gating: audit-first — verify schema + flow thật trước khi sửa, mỗi step cần Wyatt confirm. KHÔNG sửa wallet/transaction/commission/cron logic khi chưa đọc code thật. Ref: docs/guides/adp-protocol.md §2"}'
                    exit 0
                fi
                ;;
        esac
    fi
fi

# All clear
echo '{"continue": true}'
exit 0
