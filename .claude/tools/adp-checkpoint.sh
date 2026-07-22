#!/bin/bash
# ============================================================
# ADP Checkpoint — con đường DUY NHẤT để một phase thành DONE.
# Giao dịch nguyên tử: chạy GATE_FULL → từ chối nếu đỏ →
# git commit code → STATUS: DONE + EVIDENCE → evidence commit
# → stamp project_state_hash.
#
# Usage:
#   bash adp-checkpoint.sh [--verify-only] [-m "concern message"] [project_root]
#
#   --verify-only : chạy GATE_FULL + structured summary, KHÔNG commit,
#                   KHÔNG đổi STATUS. Exit code = exit code của gate.
#   -m            : commit message concern (checkpoint mode).
#   project_root  : default = cwd (tự tìm ADP:MANIFEST từ đó đi lên).
#
# Formats: docs/guides/adp-protocol.md §3
# ============================================================

set -o pipefail

_ADPTD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$_ADPTD/../hooks/adp-lib.sh"
[ -f "$LIB" ] || { echo "FATAL: adp-lib.sh not found at $LIB" >&2; exit 1; }
# shellcheck source=../hooks/adp-lib.sh
source "$LIB"

# ----------------------------------------------------------
# REVIEW artifact validation (Tier-2 #2 — output-evaluator judge).
# Gate REVIEW: PASS ref=<file> được verify CỨNG: artifact tồn tại + verdict=APPROVE.
# Không có ref= → giữ behavior cũ (legacy manual attest). Bash KHÔNG gọi agent —
# Claude sinh artifact ngoài luồng, script chỉ ENFORCE nó thật.
# ----------------------------------------------------------
adp_review_verdict() {  # $1=root $2=ref → echo APPROVE|NEEDS_REVIEW|REJECT|MISSING|PARSE_ERR|NONE
    local root="$1" ref="$2" f
    case "$ref" in /*) f="$ref" ;; *) f="$root/$ref" ;; esac
    [ -f "$f" ] || { echo "MISSING"; return; }
    python3 - "$f" <<'PY' 2>/dev/null || echo "PARSE_ERR"
import sys, json
try:
    print(str(json.load(open(sys.argv[1])).get("verdict", "")).upper() or "NONE")
except Exception:
    print("PARSE_ERR")
PY
}

# ----------------------------------------------------------
# SMOKE gate (2026-07-19, Wyatt directive sau spec 07).
#
# Spec 07 ship 3 lỗi mà 107 test xanh + mypy sạch + 3 vòng review KHÔNG thấy:
# model id sai provider, model không serverless, log bị uvicorn nuốt. Cả ba chỉ
# lộ khi có gói tin thật / tiến trình thật / pixel thật. Test chứng minh code
# đúng trong môi trường TEST; smoke chứng minh hệ thống đúng trong môi trường THẬT.
#
# Chặn cứng như REVIEW, nhưng có lối thoát `SMOKE: N/A <lý do>` — vì bắt smoke
# cho phase không có mặt runtime (vd spec 06 F2: typing + conftest) sẽ đẻ ra tick
# bừa, mà tick bừa tệ hơn không có ô tick: nó TRÔNG như đã kiểm.
# Bắt buộc là KHAI BÁO, không phải CHẠY.
# ----------------------------------------------------------
smoke_validate() {  # dùng global SMOKE_VAL/SMOKE_REF/ROOT; set SMOKE_NOTE; exit 1 nếu xấu
    local f art_sha work_sha
    case "$SMOKE_REF" in /*) f="$SMOKE_REF" ;; *) f="$ROOT/$SMOKE_REF" ;; esac
    [ -f "$f" ] || {
        echo "CHECKPOINT REFUSED — SMOKE: artifact '${SMOKE_REF}' không tồn tại."
        exit 1
    }
    grep -qE '^VERDICT:[[:space:]]*PASS' "$f" || {
        echo "CHECKPOINT REFUSED — SMOKE: '${SMOKE_REF}' chưa có 'VERDICT: PASS'."
        exit 1
    }
    grep -qE '^SMOKED_BY:[[:space:]]*[^[:space:]]' "$f" || {
        echo "CHECKPOINT REFUSED — SMOKE: '${SMOKE_REF}' thiếu SMOKED_BY (ai chạy?)."
        exit 1
    }
    # Placeholder còn nguyên = scaffold rồi stamp, chưa chạy gì.
    if grep -qE '^\(dán\)?$|^\(dán output\)$' "$f"; then
        echo "CHECKPOINT REFUSED — SMOKE: '${SMOKE_REF}' còn placeholder '(dán…)' — smoke chưa chạy thật."
        exit 1
    fi
    art_sha=$(sed -n 's/^- diff_sha256:[[:space:]]*//p' "$f" | head -1)
    [ -n "$art_sha" ] || {
        echo "CHECKPOINT REFUSED — SMOKE: '${SMOKE_REF}' chưa bind diff. Bind: bash .claude/tools/adp-smoke.sh stamp \"$ROOT\" ${SMOKE_REF}"
        exit 1
    }
    work_sha=$(adp_work_diff_sha "$ROOT")
    [ "$art_sha" = "$work_sha" ] || {
        echo "CHECKPOINT REFUSED — SMOKE: diff ĐỔI sau smoke (artifact=${art_sha:0:12} ≠ working=${work_sha:0:12}). Smoke cũ không áp dụng cho code hiện tại — chạy lại rồi stamp."
        exit 1
    }
    SMOKE_NOTE="PASS(bound=${work_sha:0:12})"
    echo "SMOKE GATE: PASS · diff=${work_sha:0:12} · ref=${SMOKE_REF}"
}

review_validate_artifact() {  # $1=tier; dùng global REVIEW_VAL/REVIEW_REF/ROOT; set REVIEW_NOTE; exit 1 nếu xấu
    local tier="$1" verd
    if [ -z "$REVIEW_REF" ]; then
        REVIEW_NOTE="PASS"
        echo "REVIEW GATE: ${REVIEW_VAL} · tier=${tier} (no artifact ref — legacy manual attest)"
        adp_audit_event "$ROOT" gate=review outcome=PASS-legacy tier="$tier" verdict=none model=none diff="$(adp_work_diff_sha "$ROOT")" spec="${SPEC_ID:-}" phase="${PHASE_ID:-}"
        return 0
    fi
    verd=$(adp_review_verdict "$ROOT" "$REVIEW_REF")
    case "$verd" in
        APPROVE)
            local artf art_sha work_sha model href hfile hsha
            case "$REVIEW_REF" in /*) artf="$REVIEW_REF" ;; *) artf="$ROOT/$REVIEW_REF" ;; esac
            art_sha=$(adp_artifact_field "$artf" diff_sha256)
            model=$(adp_artifact_field "$artf" model)
            work_sha=$(adp_work_diff_sha "$ROOT")
            # P1 diff-binding: verdict phải gắn vào ĐÚNG diff sắp commit (hash do script tính).
            if [ -z "$art_sha" ]; then
                if [ "$tier" = "high" ]; then
                    echo "CHECKPOINT REFUSED — REVIEW (high): artifact '${REVIEW_REF}' thiếu diff_sha256 (chưa bind). Bind: bash .claude/tools/adp-review.sh stamp \"$ROOT\" <verdict.json> ${REVIEW_REF}"
                    exit 1
                fi
                echo "  ⚠️ REVIEW unbound: '${REVIEW_REF}' chưa có diff_sha256 (legacy) — tier=${tier} cho qua; nên bind qua adp-review.sh stamp."
            elif [ -z "$work_sha" ]; then
                echo "CHECKPOINT REFUSED — REVIEW: không hash được working diff (${ROOT} có phải git repo?)."
                exit 1
            elif [ "$art_sha" != "$work_sha" ]; then
                adp_audit_event "$ROOT" gate=review outcome=REFUSED reason=diff-mismatch tier="$tier" verdict=APPROVE model="${model:-?}" artifact_sha="$art_sha" diff="$work_sha" spec="${SPEC_ID:-}" phase="${PHASE_ID:-}"
                echo "CHECKPOINT REFUSED — REVIEW: diff ĐỔI sau review (artifact=${art_sha:0:12} ≠ working=${work_sha:0:12}). Verdict cũ không áp dụng cho diff hiện tại — chấm lại rồi stamp."
                exit 1
            fi
            # RISK:high — auto-verdict KHÔNG đủ; bắt buộc human-review artifact RIÊNG, bound cùng diff.
            if [ "$tier" = "high" ]; then
                href=$(printf '%s' "$REVIEW_VAL" | sed -n 's/.*human=\([^[:space:]]*\).*/\1/p')
                if [ -z "$href" ]; then
                    adp_audit_event "$ROOT" gate=review outcome=REFUSED reason=high-no-human tier=high verdict=APPROVE model="${model:-?}" diff="$work_sha" spec="${SPEC_ID:-}" phase="${PHASE_ID:-}"
                    echo "CHECKPOINT REFUSED — REVIEW (high): thiếu 'human=<file>' trong REVIEW line. Auto-verdict (model=${model:-?}) KHÔNG đủ cho RISK:high. Tạo: bash .claude/tools/adp-review.sh human \"$ROOT\" <file> → Wyatt đọc diff → thêm 'human=<file>' vào REVIEW."
                    exit 1
                fi
                case "$href" in /*) hfile="$href" ;; *) hfile="$ROOT/$href" ;; esac
                [ -f "$hfile" ] || { echo "CHECKPOINT REFUSED — REVIEW (high): human artifact '${href}' không tồn tại."; exit 1; }
                grep -qE "REVIEWED_BY:[ ]*[^ ]" "$hfile" || { echo "CHECKPOINT REFUSED — REVIEW (high): '${href}' chưa có REVIEWED_BY (Wyatt chưa ký review)."; exit 1; }
                hsha=$(grep -m1 'diff_sha256:' "$hfile" | sed 's/.*diff_sha256:[ ]*//; s/[ ]*$//')
                [ "$hsha" = "$work_sha" ] || { echo "CHECKPOINT REFUSED — REVIEW (high): human review bound diff khác (${hsha:0:12} ≠ ${work_sha:0:12}) — review lại đúng diff hiện tại."; exit 1; }
            fi
            REVIEW_NOTE="PASS(judge=APPROVE,model=${model:-?},bound=${work_sha:0:12},tier=${tier})"
            echo "REVIEW GATE: PASS · judge=APPROVE · model=${model:-?} · diff=${work_sha:0:12} · ref=${REVIEW_REF} · tier=${tier}"
            [ "$tier" = "high" ] && echo "  ↳ + human sync review bound & signed (REVIEWED_BY ok)."
            adp_audit_event "$ROOT" gate=review outcome=PASS tier="$tier" verdict=APPROVE model="${model:-?}" diff="$work_sha" ref="$REVIEW_REF" spec="${SPEC_ID:-}" phase="${PHASE_ID:-}"
            return 0 ;;
        MISSING)
            echo "CHECKPOINT REFUSED — REVIEW (tier=${tier}): artifact '${REVIEW_REF}' KHÔNG tồn tại. Chạy output-evaluator (review diff) → lưu JSON verdict vào path đó → checkpoint lại."
            exit 1 ;;
        *)
            echo "CHECKPOINT REFUSED — REVIEW (tier=${tier}): judge verdict='${verd}' (≠ APPROVE) tại '${REVIEW_REF}'. RESOLVE/WAIVE → chấm lại bằng output-evaluator → checkpoint."
            exit 1 ;;
    esac
}

VERIFY_ONLY=0
MSG=""
START_DIR="$PWD"
while [ $# -gt 0 ]; do
    case "$1" in
        --verify-only) VERIFY_ONLY=1 ;;
        -m) shift; MSG="$1" ;;
        *) START_DIR="$1" ;;
    esac
    shift
done

ROOT=$(adp_find_root "$START_DIR") || { echo "FATAL: không tìm thấy ADP:MANIFEST từ $START_DIR đi lên." >&2; exit 1; }
SPEC_DIR=$(adp_manifest_get "$ROOT" SPEC_DIR)
SPEC_DIR=${SPEC_DIR:-docs/tasks}

BLOCK=$(adp_active_block "$ROOT" "$SPEC_DIR") || { echo "FATAL: không có phase nào STATUS: IN_PROGRESS trong $ROOT/$SPEC_DIR." >&2; exit 1; }
SPEC_FILE=$(echo "$BLOCK" | adp_block_get SPEC_FILE)
PHASE_ID=$(echo "$BLOCK" | grep -m1 'ADP:PHASE' | sed 's/.*ADP:PHASE[ ]*//; s/[ ]*-->.*//')
SPEC_ID=$(basename "$SPEC_FILE" .md)
GATE_CMD=$(echo "$BLOCK" | adp_block_gate_full)
RISK_VAL=$(echo "$BLOCK" | adp_block_get RISK)
[ -z "$GATE_CMD" ] && { echo "FATAL: phase ${PHASE_ID} không có GATE/GATE_FULL." >&2; exit 1; }

# ----------------------------------------------------------
# 0. Governance gates (v1.3 — DEC-019). Chỉ chạy ở checkpoint mode;
#    --verify-only là read-only convenience, không gate governance.
# ----------------------------------------------------------
TIER=$(adp_risk_tier "$RISK_VAL")
REVIEW_VAL=$(echo "$BLOCK" | adp_block_get REVIEW)
REVIEW_REF=$(printf '%s' "$REVIEW_VAL" | sed -n 's/.*ref=\([^[:space:]]*\).*/\1/p')
SMOKE_VAL=$(echo "$BLOCK" | adp_block_get SMOKE)
SMOKE_REF=$(printf '%s' "$SMOKE_VAL" | sed -n 's/.*ref=\([^[:space:]]*\).*/\1/p')
SMOKE_NOTE=""
WAIVER=$(echo "$BLOCK" | adp_block_get RISK_WAIVER)
ALLOWED=$(echo "$BLOCK" | adp_block_get ALLOWED_FILES)
RISK_PATHS_M=$(adp_manifest_get "$ROOT" RISK_PATHS)
REVIEW_NOTE=""

if [ $VERIFY_ONLY -eq 0 ]; then
    # E10 change-control: frozen sprint-spec contract phải không drift mid-sprint.
    # Lock vắng (chưa freeze) → rc0 allow. STATUS/EVIDENCE/RETRY/REVIEW excluded ở
    # adp_spec_lock_compute (đó là execution metadata, không phải contract).
    DRIFT=$(adp_spec_lock_verify "$ROOT" "$SPEC_FILE" 2>&1) || {
        echo "CHECKPOINT REFUSED — SPEC LOCK (E10): frozen contract của ${SPEC_ID} đã ĐỔI mid-sprint (${DRIFT}). GOAL/APPROACH/GATE/ALLOWED_FILES/RISK là frozen — sửa = phải re-approve spec + adp_spec_lock_write lại. Ref: docs/guides/adp-protocol.md §3, .claude/adp-operating-prompt.md §6."
        exit 1
    }

    # Floor rule: ALLOWED_FILES ∩ RISK_PATHS ≠ ∅ ⇒ floor = medium.
    # Hạ dưới floor chỉ qua RISK_WAIVER (Wyatt viết lúc duyệt spec).
    if [ "$TIER" = "low" ] && [ -n "$RISK_PATHS_M" ]; then
        OVERLAP=$(adp_allowed_risk_overlap "$ALLOWED" "$RISK_PATHS_M") || OVERLAP=""
        if [ -n "$OVERLAP" ]; then
            if [ -z "$WAIVER" ]; then
                echo "CHECKPOINT REFUSED — FLOOR RULE (v1.3): phase ${PHASE_ID} RISK: low nhưng ALLOWED_FILES chạm RISK_PATHS ('${OVERLAP}') — floor là medium. Sửa RISK trong spec, hoặc Wyatt thêm 'RISK_WAIVER: <rationale>' vào block. Ref: docs/guides/adp-protocol.md §2."
                exit 1
            fi
            echo "⚠️ FLOOR WAIVED: '${OVERLAP}' chạm RISK_PATHS — RISK_WAIVER: ${WAIVER}"
        fi
    fi

    # SMOKE gate (2026-07-19). Chạy TRƯỚC review: smoke đo hệ thống thật, và nếu nó đỏ
    # thì không có lý do gì tốn một vòng review cho code chưa chạy được.
    case "$SMOKE_VAL" in
        PASS*)
            [ -n "$SMOKE_REF" ] || {
                echo "CHECKPOINT REFUSED — SMOKE: 'SMOKE: PASS' phải kèm 'ref=<artifact>'. Lời khai trần không phải bằng chứng — đó chính là thứ đã để 3 lỗi lọt ở spec 07."
                exit 1
            }
            smoke_validate
            ;;
        N/A*|NA*|n/a*)
            reason=$(printf '%s' "$SMOKE_VAL" | sed -E 's#^(N/A|NA|n/a)[[:space:]]*##')
            if [ ${#reason} -lt 12 ]; then
                echo "CHECKPOINT REFUSED — SMOKE: 'N/A' phải kèm LÝ DO cụ thể (≥12 ký tự), vd 'N/A — phase chỉ sửa typing + conftest, không có mặt runtime nào'. N/A trần là tick bừa."
                exit 1
            fi
            SMOKE_NOTE="N/A(${reason})"
            echo "SMOKE GATE: N/A — ${reason}"
            ;;
        *)
            echo "CHECKPOINT REFUSED — SMOKE GATE: phase ${PHASE_ID} chưa có dòng 'SMOKE:' trong ADP block."
            echo "  Spec 07 ship 3 lỗi mà 107 test xanh + mypy sạch + 3 vòng review đều KHÔNG thấy"
            echo "  (model id sai provider · model không serverless · log bị uvicorn nuốt). Cả ba chỉ"
            echo "  lộ khi chạy THẬT. Test đo môi trường test; smoke đo môi trường thật."
            echo "  Có mặt runtime  → bash .claude/tools/adp-smoke.sh new \"$ROOT\" docs/smokes/<spec>-<phase>.md ${PHASE_ID}"
            echo "                    chạy tay → điền OBSERVED → stamp → ghi 'SMOKE: PASS ref=…'"
            echo "  Không có        → ghi 'SMOKE: N/A <lý do cụ thể>' vào block."
            exit 1
            ;;
    esac

    # REVIEW gate: review là GATE, không phải advice (rider Wyatt 2026-06-10).
    case "$TIER" in
        high|medium)
            case "$REVIEW_VAL" in
                PASS*) review_validate_artifact "$TIER" ;;
                *)
                    echo "CHECKPOINT REFUSED — REVIEW GATE (tier=${TIER}): phase ${PHASE_ID} chưa có 'REVIEW: PASS ref=<artifact>' trong ADP block. Chạy independent review (reviewer subagent / /code-review), RESOLVE hoặc WAIVE mọi finding, ghi REVIEW: PASS ref=... (verifier ≠ doer — KHÔNG tự ghi PASS khi chưa có artifact thật) rồi checkpoint lại."
                    [ "$TIER" = "high" ] && echo "Tier high: Wyatt sync diff review cũng bắt buộc TRƯỚC checkpoint."
                    exit 1
                    ;;
            esac
            ;;
        low)
            case "$REVIEW_VAL" in
                PASS*) review_validate_artifact "low" ;;
                *)
                    # Mechanical skip: CHỈ khi diff toàn docs/**, *.md (máy verify, không phải doer tự khai)
                    CHANGED=$(cd "$ROOT" && git status --porcelain 2>/dev/null | awk '{print $NF}')
                    NON_DOCS=$(echo "$CHANGED" | grep -v '^docs/' | grep -v '\.md$' | grep -v '^$' || true)
                    if [ -z "$NON_DOCS" ]; then
                        REVIEW_NOTE="skip(docs-only)"
                        echo "REVIEW GATE: skip(docs-only) — machine-verified, diff không chạm source file nào."
                    else
                        echo "CHECKPOINT REFUSED — REVIEW GATE (tier=low): diff chạm source file ($(echo "$NON_DOCS" | head -3 | tr '\n' ' ')...) nên cần LIGHT review (blocking, timeboxed). Chạy reviewer light / /code-review low effort, ghi 'REVIEW: PASS ref=<artifact>' vào block rồi checkpoint lại. Docs-only diff mới được skip tự động."
                        exit 1
                    fi
                    ;;
            esac
            ;;
    esac
fi

# ----------------------------------------------------------
# 1. Run GATE_FULL — structured summary (framework-agnostic)
# ----------------------------------------------------------
T0=$(date +%s)
OUT=$(cd "$ROOT" && bash -c "$GATE_CMD" 2>&1)
RC=$?
T1=$(date +%s)
DUR=$((T1 - T0))

echo "ADP CHECKPOINT — ${SPEC_ID} · phase ${PHASE_ID}"
if [ $RC -eq 0 ]; then
    echo "GATE_FULL: PASS · exit=0 · duration=${DUR}s · cmd: ${GATE_CMD}"
else
    echo "GATE_FULL: FAIL · exit=${RC} · duration=${DUR}s · cmd: ${GATE_CMD}"
    echo "failed-tail:"
    echo "$OUT" | tail -3 | sed 's/^/  /'
fi

if [ $VERIFY_ONLY -eq 1 ]; then
    exit $RC
fi

if [ $RC -ne 0 ]; then
    echo "CHECKPOINT REFUSED — phase ${PHASE_ID} giữ nguyên IN_PROGRESS. RETRY policy áp dụng (max 3 → STOP + rollback + báo Wyatt)."
    exit 1
fi

# ----------------------------------------------------------
# 2. Git commit code (commit #1)
# ----------------------------------------------------------
cd "$ROOT" || exit 1
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "FATAL: $ROOT không phải git repo — EVIDENCE cần commit hash." >&2; exit 1; }

[ -z "$MSG" ] && MSG="checkpoint"
git add -A
if git diff --cached --quiet 2>/dev/null; then
    HASH=$(git rev-parse --short HEAD)
    echo "COMMIT: working tree sạch — dùng HEAD ${HASH} làm evidence."
else
    CHANGED=$(git diff --cached --name-only | head -10 | tr '\n' ' ')
    git commit -q -m "adp/${SPEC_ID} phase-${PHASE_ID}: ${MSG}" || { echo "FATAL: git commit thất bại." >&2; exit 1; }
    HASH=$(git rev-parse --short HEAD)
    echo "COMMIT: ${HASH} \"adp/${SPEC_ID} phase-${PHASE_ID}: ${MSG}\" · files: ${CHANGED}"
fi

# ----------------------------------------------------------
# 3. STATUS → DONE + EVIDENCE (script ghi, không phải agent)
# ----------------------------------------------------------
TS=$(date +%Y-%m-%dT%H:%M)
EVLINE="EVIDENCE: commit=${HASH}, gate_exit=0, duration=${DUR}s, review=${REVIEW_NOTE:-n/a}, smoke=${SMOKE_NOTE:-n/a}, ran=${TS}"
python3 - "$SPEC_FILE" "$PHASE_ID" "$EVLINE" <<'PY' || { echo "FATAL: không update được spec STATUS." >&2; exit 1; }
import sys, re
path, phase, ev = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
pat = re.compile(r'(<!-- ADP:PHASE[ ]*' + re.escape(phase) + r'[ ]*-->\n)(.*?)(<!-- /ADP -->)', re.S)
m = pat.search(s)
if not m:
    sys.exit(1)
body = m.group(2)
body = re.sub(r'^EVIDENCE:.*\n?', '', body, flags=re.M)          # strip stale evidence
body, n = re.subn(r'STATUS:[ ]*IN_PROGRESS', 'STATUS: DONE\n' + ev, body, count=1)
if n != 1:
    sys.exit(1)
open(path, 'w').write(s[:m.start(2)] + body + s[m.end(2):])
PY

# ----------------------------------------------------------
# 4. Next phase: auto-advance (v1.3) khi low→low — APPROACH đã được
#    Wyatt duyệt trong spec. Mọi tier khác → suggest-only
#    (P1: step N chạy khi N−1 accepted).
# ----------------------------------------------------------
NEXT_BLOCK=$(awk '
    /<!-- ADP:PHASE/ { buf = $0 "\n"; inb = 1; next }
    inb              { buf = buf $0 "\n" }
    /<!-- \/ADP -->/ { if (inb) { inb = 0; if (buf ~ /STATUS:[ ]*TODO/) { printf "%s", buf; exit } } }
' "$SPEC_FILE" 2>/dev/null)
ADVANCED=0
NEXT_ID=""
NEXT_TIER=""
if [ -n "$NEXT_BLOCK" ]; then
    NEXT_ID=$(echo "$NEXT_BLOCK" | grep -m1 'ADP:PHASE' | sed 's/.*ADP:PHASE[ ]*//; s/[ ]*-->.*//')
    NEXT_GOAL=$(echo "$NEXT_BLOCK" | adp_block_get GOAL)
    NEXT_RISK=$(echo "$NEXT_BLOCK" | adp_block_get RISK)
    NEXT_TIER=$(adp_risk_tier "$NEXT_RISK")
    if [ "$TIER" = "low" ] && [ "$NEXT_TIER" = "low" ]; then
        python3 - "$SPEC_FILE" "$NEXT_ID" <<'PY' && ADVANCED=1
import sys, re
path, phase = sys.argv[1], sys.argv[2]
s = open(path).read()
pat = re.compile(r'(<!-- ADP:PHASE[ ]*' + re.escape(phase) + r'[ ]*-->\n)(.*?)(<!-- /ADP -->)', re.S)
m = pat.search(s)
if not m:
    sys.exit(1)
body, n = re.subn(r'STATUS:[ ]*TODO', 'STATUS: IN_PROGRESS', m.group(2), count=1)
if n != 1:
    sys.exit(1)
open(path, 'w').write(s[:m.start(2)] + body + s[m.end(2):])
PY
    fi
fi

# ----------------------------------------------------------
# 5. project_state_hash + review queue + evidence commit (commit #2)
# ----------------------------------------------------------
STATE_HASH=$(adp_state_hash "$ROOT" "$SPEC_DIR")
mkdir -p "$ROOT/docs"
echo "${STATE_HASH} @ ${TS} ${SPEC_ID} phase-${PHASE_ID} DONE" >> "$ROOT/docs/.adp-state-hash"

# Async diff review queue (medium/low — tier high đã được Wyatt review sync trước checkpoint)
if [ "$TIER" != "high" ]; then
    QF="$ROOT/docs/memory/REVIEW_QUEUE.md"
    mkdir -p "$ROOT/docs/memory"
    [ -f "$QF" ] || printf '# ADP Review Queue — async diff review (v1.3, DEC-019)\n\nCheckpoint tier medium/low ghi vào đây; Wyatt review batch, tick [x] khi đã xem.\nRevert 1 lệnh kèm sẵn (evidence commit revert riêng nếu cần).\n\n' > "$QF"
    echo "- [ ] ${TS} · ${SPEC_ID} phase-${PHASE_ID} · tier=${TIER} · review=${REVIEW_NOTE} · smoke=${SMOKE_NOTE:-n/a} · commit=${HASH} · revert: git revert ${HASH}" >> "$QF"
fi

# L3 roadmap view — sinh lại từ L1×L2 sau khi STATUS đã thành DONE.
# Generator KHÔNG ghi vào L1 (docs/ROADMAP.md) — L1 là tầng ý định, chỉ người viết.
# Lỗi generator không được làm hỏng checkpoint: view sai < checkpoint vỡ.
ROADMAP_OUT=""
if [ -x "$ROOT/.claude/tools/adp-roadmap.sh" ] && [ -f "$ROOT/docs/ROADMAP.md" ]; then
    ROADMAP_OUT=$(bash "$ROOT/.claude/tools/adp-roadmap.sh" "$ROOT" 2>&1) || \
        ROADMAP_OUT="⚠️ adp-roadmap.sh lỗi (checkpoint vẫn tiếp tục): ${ROADMAP_OUT}"
fi

# HTML dashboards (gitignored views) — luôn phản ánh L3/spec vừa sinh (Wyatt 2026-07-22
# "dashboard luôn phản ánh thực tế" + merge adp-progress-dashboard). Best-effort: KHÔNG
# git-add (cả hai untracked+gitignored), lỗi generator KHÔNG làm hỏng checkpoint — view sai
# < checkpoint vỡ, cùng luật với L3. ~0.04s + ~0.28s.
#   1) adp-dashboard.html      — spine status + audit logs + roadmap coverage (tool local)
#   2) adp-progress-dashboard.html — spec cards + phase drawer + roadmap TIMELINE (tool workspace)
if [ -x "$ROOT/.claude/tools/adp-dashboard.sh" ]; then
    bash "$ROOT/.claude/tools/adp-dashboard.sh" >/dev/null 2>&1 \
        || echo "⚠️ adp-dashboard.sh lỗi (checkpoint vẫn tiếp tục; dashboard có thể cũ)"
fi
_WS_PROG="$(cd "$ROOT/.." 2>/dev/null && pwd)/.claude/tools/adp-progress-dashboard.sh"
if [ -x "$_WS_PROG" ]; then
    bash "$_WS_PROG" "$ROOT/docs/adp-progress-dashboard.html" "$ROOT" >/dev/null 2>&1 \
        || echo "⚠️ adp-progress-dashboard.sh lỗi (checkpoint vẫn tiếp tục; progress dashboard có thể cũ)"
fi

git add "$SPEC_FILE" "docs/.adp-state-hash" 2>/dev/null
[ -f "$ROOT/docs/memory/REVIEW_QUEUE.md" ] && git add "docs/memory/REVIEW_QUEUE.md" 2>/dev/null
[ -f "$ROOT/docs/ROADMAP-STATUS.md" ] && git add "docs/ROADMAP-STATUS.md" "docs/.roadmap-denominator.log" 2>/dev/null
git commit -q -m "adp/${SPEC_ID} phase-${PHASE_ID}: checkpoint evidence" 2>/dev/null
EV_HASH=$(git rev-parse --short HEAD)

echo "STATUS: DONE · EVIDENCE stamped (evidence commit ${EV_HASH}) · STATE_HASH: ${STATE_HASH}"
[ -n "$ROADMAP_OUT" ] && printf 'ROADMAP L3:\n%s\n' "$ROADMAP_OUT"
[ "$TIER" != "high" ] && echo "REVIEW_QUEUE: appended → docs/memory/REVIEW_QUEUE.md (Wyatt review async; revert: git revert ${HASH})"

if [ "$ADVANCED" -eq 1 ]; then
    echo "AUTO-ADVANCE (low→low): phase ${NEXT_ID} → IN_PROGRESS — ${NEXT_GOAL}"
    echo "NEXT: ANCHOR ritual BẮT BUỘC trước khi code (re-read block, entry re-verify — GATE_FULL vừa xanh nên re-verify đã thỏa nếu tiếp tục ngay). Session mới nếu context > ~50% (protocol §5.2)."
elif [ -n "$NEXT_ID" ]; then
    echo "NEXT-UP (suggest-only): phase ${NEXT_ID} — ${NEXT_GOAL}${NEXT_RISK:+ · RISK: ${NEXT_RISK}}"
    case "$TIER" in
        high) echo "NEXT: Wyatt review diff sync → approve → flip phase kế IN_PROGRESS → ANCHOR ritual (protocol §5.2)." ;;
        *)    echo "NEXT: diff review async qua REVIEW_QUEUE.md. Phase kế tier=${NEXT_TIER} — medium: 1 confirm Wyatt tại ANCHOR; high: per-step confirm. Flip IN_PROGRESS sau confirm → ANCHOR ritual." ;;
    esac
else
    echo "NEXT-UP: không còn phase TODO trong spec này — milestone gate / meta-sync / SESSION_LOG."
fi
exit 0
