#!/bin/bash
# =============================================================================
# adp-review.sh — wrapper TẤT ĐỊNH cho REVIEW artifact (P1 diff-binding).
# Hash do SCRIPT tính (không tin LLM tự khai). Biến "lời khai" → "bằng chứng":
# verdict được gắn cứng vào diff_sha256 của ĐÚNG diff hiện tại.
#
# Modes:
#   hash  <repo>                               -> in diff_sha256 hiện tại (git diff HEAD)
#   stamp <repo> <verdict_in.json> <out.json>  -> ghi artifact canonical, diff_sha256 do
#                                                  SCRIPT chèn (đè mọi giá trị LLM tự khai)
#   human <repo> <out.md>                      -> stub human-review bound vào diff (RISK:high)
#   red   <repo> <task_id> <acc_cmd> [files]   -> P6 RED-proof: chạy acc_cmd, BẮT BUỘC fail
#                                                  (RED) trước code mới record; pass→REFUSE
#   dor   <repo> <handoff.json> [ack]          -> E7 DoR pre-spawn gate: handoff-valid +
#                                                  acc dry-run + RED-proof + risk∩files (ack)
#
# Flow điển hình trong session:
#   1. Claude invoke output-evaluator agent → lưu verdict JSON thô (vd /tmp/v.json)
#   2. bash adp-review.sh stamp <repo> /tmp/v.json docs/reviews/<spec>-phase-<id>.json
#   3. Ghi REVIEW: PASS ref=docs/reviews/<spec>-phase-<id>.json  (high: + human=<file>)
#   4. adp-checkpoint.sh tự tính lại hash & REFUSE nếu lệch
# =============================================================================
set -uo pipefail

_ADPTD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$_ADPTD/../hooks/adp-lib.sh"
[ -f "$LIB" ] || { echo "FATAL: adp-lib.sh not found at $LIB" >&2; exit 1; }
# shellcheck source=../hooks/adp-lib.sh
source "$LIB"

mode="${1:-}"; repo="${2:-}"
[ -n "$mode" ] && [ -n "$repo" ] || { echo "usage: adp-review.sh {hash|stamp|human} <repo> [...]" >&2; exit 2; }

SHA=$(adp_work_diff_sha "$repo")
[ -n "$SHA" ] || { echo "FATAL: '$repo' không phải git repo (cần để hash diff)." >&2; exit 1; }
TS=$(date +%Y-%m-%dT%H:%M)

case "$mode" in
    hash)
        echo "$SHA"
        ;;
    stamp)
        in="${3:-}"; out="${4:-}"
        [ -f "$in" ] || { echo "FATAL: verdict input '$in' không tồn tại." >&2; exit 1; }
        [ -n "$out" ] || { echo "FATAL: thiếu output artifact path." >&2; exit 1; }
        mkdir -p "$(dirname "$out")"
        python3 - "$in" "$out" "$SHA" "$TS" <<'PY' || { echo "FATAL: stamp lỗi (verdict JSON hợp lệ?)." >&2; exit 1; }
import sys, json
src, out, sha, ts = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
v = json.load(open(src))
if not isinstance(v, dict):
    raise SystemExit("verdict không phải JSON object")
v["diff_sha256"] = sha          # SCRIPT-owned, đè mọi giá trị LLM tự khai
v["stamped_at"] = ts
v.setdefault("model", "unknown")
json.dump(v, open(out, "w"), ensure_ascii=False, indent=2)
print("stamped:", out, "| verdict:", v.get("verdict"), "| diff:", sha[:12], "| model:", v.get("model"))
PY
        ;;
    human)
        out="${3:-}"
        [ -n "$out" ] || { echo "FATAL: thiếu output path." >&2; exit 1; }
        [ -f "$out" ] && { echo "FATAL: '$out' đã tồn tại — không ghi đè human review." >&2; exit 1; }
        mkdir -p "$(dirname "$out")"
        cat > "$out" <<EOF
# Human Sync Review (RISK:high) — bound to diff

diff_sha256: $SHA
generated: $TS
repo: $repo

> Đọc \`git -C "$repo" diff HEAD\`. Xác nhận 3 trục money-code:
>   1. amount / số dư / commission   2. auth / session   3. side-effect (ghi DB, gọi ngoài)
> Review XONG đúng diff này → giữ nguyên diff_sha256 ở trên, điền NOTES, giữ dòng REVIEWED_BY.
> Nếu diff đổi sau khi tạo file này, checkpoint sẽ REFUSE (hash lệch) — tạo lại.

REVIEWED_BY: wyatt
NOTES:
-
EOF
        echo "human-review stub: $out (diff ${SHA:0:12}). Đọc diff → điền NOTES → giữ REVIEWED_BY."
        ;;
    red)
        # P6 RED-proof: run the task's acceptance_cmd; it MUST fail (RED) before code.
        # If it passes now, it measures nothing → REFUSE to record (closes "test luôn-xanh").
        task_id="${3:-}"; acc="${4:-}"; files_csv="${5:-}"
        [ -n "$task_id" ] && [ -n "$acc" ] || { echo "usage: adp-review.sh red <repo> <task_id> <acceptance_cmd> [files_csv]" >&2; exit 2; }
        ( cd "$repo" && bash -c "$acc" ) >/dev/null 2>&1; rc=$?
        if [ "$rc" -eq 0 ]; then
            echo "REFUSE: acceptance_cmd PASSED (exit 0) before code — not a valid gate-test (measures nothing). Author a test that FAILS first (RED)." >&2
            adp_audit_event "$repo" gate=red-proof outcome=REFUSE task="$task_id" reason=green-before-code
            exit 1
        fi
        adp_red_proof_record "$repo" "$task_id" "$(adp_cmd_sha "$acc")" "$rc" "$files_csv"
        adp_audit_event "$repo" gate=red-proof outcome=RECORDED task="$task_id" red_exit="$rc"
        echo "RED recorded: task=$task_id red_exit=$rc acc_sha=$(adp_cmd_sha "$acc" | cut -c1-12)"
        ;;
    dor)
        # E7 DoR (Definition of Ready) pre-spawn gate. rc0 = ready to spawn coder/bug-fixer.
        hand="${3:-}"; ack="${4:-}"
        [ -f "$hand" ] || { echo "DoR FAIL:no-handoff" >&2; exit 1; }
        reasons=""
        hv=$(adp_handoff_validate "$hand") || reasons="$reasons handoff:$hv"
        task_id=$(adp_artifact_field "$hand" task_id)
        acc=$(adp_artifact_field "$hand" acceptance_cmd)
        files_csv=$(python3 - "$hand" <<'PY' 2>/dev/null || true
import sys, json
try:
    print(",".join(json.load(open(sys.argv[1])).get("files", [])))
except Exception:
    pass
PY
)
        # (a) acceptance_cmd dry-run = syntax check only (does NOT execute)
        if [ -n "$acc" ]; then bash -nc "$acc" 2>/dev/null || reasons="$reasons acc-syntax"; else reasons="$reasons no-acc"; fi
        # (b) RED-proof recorded + valid (red_exit != 0)
        re=$(adp_red_proof_get "$repo" "$task_id" red_exit)
        if [ -z "$re" ]; then reasons="$reasons no-red-proof"; elif [ "$re" = "0" ]; then reasons="$reasons red-proof-bogus"; fi
        # (c) files ∩ risk_paths (case-folded) ⇒ need Wyatt-ack (4th arg = "ack")
        ov=$(adp_risk_overlap_ci "$repo" "$files_csv")
        if [ -n "$ov" ] && [ "$ack" != "ack" ]; then reasons="$reasons risk-overlap:$ov(need-ack)"; fi
        reasons=$(printf '%s' "$reasons" | sed 's/^ *//')
        if [ -z "$reasons" ]; then
            echo "DoR PASS task=$task_id"
            adp_audit_event "$repo" gate=dor outcome=PASS task="$task_id" ack="${ack:-no}"
            exit 0
        fi
        echo "DoR FAIL:$reasons" >&2
        adp_audit_event "$repo" gate=dor outcome=FAIL task="$task_id" reasons="$reasons"
        exit 1
        ;;
    *)
        echo "unknown mode: $mode (dùng hash|stamp|human|red|dor)" >&2; exit 2
        ;;
esac
