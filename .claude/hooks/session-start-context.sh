#!/bin/bash
# ============================================================
# ONFA Session Start — Inject memory context
# Nhắc Claude Code đọc memory files đầu mỗi session
# ============================================================

set -eo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd','.'))" 2>/dev/null || echo ".")

# Check which memory files exist
MEMORY_FILES=""
for f in "docs/memory/SESSION_LOG.md" "docs/memory/KNOWN_ISSUES.md" "docs/memory/DECISIONS.md"; do
    if [ -f "$CWD/$f" ]; then
        MEMORY_FILES="${MEMORY_FILES} $f"
    fi
done

# Check for canonical DB schema (single source for 262+ tables, auto-verified by onfa-meta-sync)
SCHEMA_PATH=""
if [ -f "$CWD/docs/reference/SCHEMA_REFERENCE.md" ]; then
    SCHEMA_PATH=" docs/reference/SCHEMA_REFERENCE.md"
fi

# ADP: nếu project có manifest + phase IN_PROGRESS → bơm thẳng state vào context
# (không nhắc đọc — đưa luôn bản đồ). Formats: docs/guides/adp-protocol.md §3
ADP_CTX=""
_ADPHD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADP_LIB="$_ADPHD/adp-lib.sh"
if [ -f "$ADP_LIB" ]; then
    # shellcheck source=adp-lib.sh
    source "$ADP_LIB"
    ADP_ROOT=$(adp_find_root_or_scan "$CWD" 2>/dev/null) || ADP_ROOT=""
    if [ -n "$ADP_ROOT" ]; then
        ADP_WHERE=""
        case "$CWD" in
            "$ADP_ROOT"*) : ;;
            *) ADP_WHERE=" ⚠️ Session đang ở NGOÀI project (${CWD}) — CWD discipline: nên mở session mới tại ${ADP_ROOT}. Hooks vẫn enforce qua fallback scan nhưng CLAUDE.md project KHÔNG auto-load." ;;
        esac
        SPEC_DIR=$(adp_manifest_get "$ADP_ROOT" SPEC_DIR)
        SPEC_DIR=${SPEC_DIR:-docs/tasks}
        ADP_BLOCK=$(adp_active_block "$ADP_ROOT" "$SPEC_DIR" 2>/dev/null) || ADP_BLOCK=""
        if [ -n "$ADP_BLOCK" ]; then
            ADP_CTX=" || ADP ACTIVE — resume đúng phase này, KHÔNG nhận scope khác: ${ADP_BLOCK}Lifecycle: RED→GREEN→EVIDENCE→CHECKPOINT (DONE chỉ qua adp-checkpoint.sh). Gate do stop-hook chạy thật. Ref: docs/guides/adp-protocol.md${ADP_WHERE}"
            # Floor rule warn tại ANCHOR (v1.3): bắt tier gán nhầm TRƯỚC khi code cả
            # phase ở chế độ tự trị — checkpoint sẽ refuse, warn sớm tiết kiệm công.
            A_TIER=$(adp_risk_tier "$(echo "$ADP_BLOCK" | adp_block_get RISK)") || A_TIER=""
            A_WAIVER=$(echo "$ADP_BLOCK" | adp_block_get RISK_WAIVER) || A_WAIVER=""
            A_RP=$(adp_manifest_get "$ADP_ROOT" RISK_PATHS) || A_RP=""
            if [ "$A_TIER" = "low" ] && [ -n "$A_RP" ] && [ -z "$A_WAIVER" ]; then
                A_OV=$(adp_allowed_risk_overlap "$(echo "$ADP_BLOCK" | adp_block_get ALLOWED_FILES)" "$A_RP" 2>/dev/null) || A_OV=""
                if [ -n "$A_OV" ]; then
                    ADP_CTX="${ADP_CTX} ⚠️ FLOOR RULE (v1.3): phase RISK: low nhưng ALLOWED_FILES chạm RISK_PATHS ('${A_OV}') — floor là medium. Sửa RISK trong spec (hoặc Wyatt ghi RISK_WAIVER) TRƯỚC khi code; adp-checkpoint.sh sẽ refuse nếu giữ nguyên."
                fi
            fi
        fi
        # Entry re-verify: phase DONE gần nhất phải được kiểm lại trước khi code tiếp
        DONE_BLOCK=$(adp_last_done_block "$ADP_ROOT" "$SPEC_DIR" 2>/dev/null) || DONE_BLOCK=""
        if [ -n "$DONE_BLOCK" ]; then
            D_PHASE=$(echo "$DONE_BLOCK" | grep -m1 'ADP:PHASE' | sed 's/.*ADP:PHASE[ ]*//; s/[ ]*-->.*//') || D_PHASE="?"
            D_GATE=$(echo "$DONE_BLOCK" | adp_block_gate_full) || D_GATE=""
            D_EVID=$(echo "$DONE_BLOCK" | adp_block_get EVIDENCE) || D_EVID=""
            if [ -n "$D_GATE" ]; then
                ADP_CTX="${ADP_CTX} || ENTRY RE-VERIFY (bắt buộc trước khi code): chạy lại gate của phase DONE gần nhất (${D_PHASE}): cd ${ADP_ROOT} && ${D_GATE} — Đỏ → phase trước chưa done thật: STOP, báo Wyatt, không xây tiếp."
            fi
            if [ -z "$D_EVID" ]; then
                ADP_CTX="${ADP_CTX} ⚠️ Phase ${D_PHASE} DONE nhưng THIẾU EVIDENCE → coi như CHƯA done (protocol §3); chạy adp-checkpoint.sh sau khi verify."
            fi
        fi
        # State-hash drift: state đổi ngoài checkpoint (Codex/tay người/tool khác)
        HASH_FILE="$ADP_ROOT/docs/.adp-state-hash"
        if [ -f "$HASH_FILE" ]; then
            LAST_HASH=$(tail -1 "$HASH_FILE" 2>/dev/null | awk '{print $1}') || LAST_HASH=""
            CUR_HASH=$(adp_state_hash "$ADP_ROOT" "$SPEC_DIR" 2>/dev/null) || CUR_HASH=""
            if [ -n "$LAST_HASH" ] && [ -n "$CUR_HASH" ] && [ "$CUR_HASH" != "$LAST_HASH" ]; then
                ADP_CTX="${ADP_CTX} || ⚠️ STATE DRIFT: project_state_hash hiện tại (${CUR_HASH}) ≠ stamp cuối (${LAST_HASH}) — ADP state đã đổi NGOÀI checkpoint. Đối chiếu SESSION_LOG/DECISIONS gần nhất trước khi tin STATUS."
            fi
        fi
        # HTML dashboards (gitignored views) — refresh mỗi session-open để "luôn phản ánh
        # thực tế" (Wyatt 2026-07-22 + merge adp-progress-dashboard). Best-effort, TẤT CẢ
        # output→/dev/null (TUYỆT ĐỐI không chạm JSON contract của hook ở cuối file). Đọc L3/spec
        # hiện có trên đĩa. ~0.04s + ~0.28s. KHÔNG regen L3 ở đây: L3 tracked, chỉ máy ghi lúc
        # checkpoint (giữ write-contract). Cả hai html untracked+gitignored ⇒ không git noise.
        if [ -x "$ADP_ROOT/.claude/tools/adp-dashboard.sh" ]; then
            bash "$ADP_ROOT/.claude/tools/adp-dashboard.sh" >/dev/null 2>&1 || true
        fi
        _WS_PROG="$(cd "$ADP_ROOT/.." 2>/dev/null && pwd)/.claude/tools/adp-progress-dashboard.sh"
        if [ -x "$_WS_PROG" ]; then
            bash "$_WS_PROG" "$ADP_ROOT/docs/adp-progress-dashboard.html" "$ADP_ROOT" >/dev/null 2>&1 || true
        fi
    fi
fi

if [ -n "$MEMORY_FILES" ] || [ -n "$SCHEMA_PATH" ] || [ -n "$ADP_CTX" ]; then
    CTX="SESSION START — ONFA Memory System: Đọc các file sau TRƯỚC KHI bắt đầu code:${MEMORY_FILES}${SCHEMA_PATH}. SESSION_LOG.md = context từ session trước. KNOWN_ISSUES.md = registry bugs/risks. DECISIONS.md = quyết định đã lock — KHÔNG revisit trừ khi Wyatt yêu cầu. SCHEMA_REFERENCE.md = canonical DB schema (262+ tables) — đọc nếu task chạm wiho_* / frogverse_* tables; onfa-meta-sync verify drift vs live MySQL mỗi sprint.${ADP_CTX}"
    export SS_CTX="$CTX"
    python3 -c 'import json,os; print(json.dumps({"continue": True, "additionalContext": os.environ.get("SS_CTX","")}))' 2>/dev/null \
        || echo '{"continue": true}'
else
    echo '{"continue": true}'
fi
exit 0
