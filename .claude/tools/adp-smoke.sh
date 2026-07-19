#!/bin/bash
# =============================================================================
# adp-smoke.sh — SMOKE artifact chạy TAY, bound vào diff (như adp-review.sh).
#
# VÌ SAO TỒN TẠI. Spec 07 ship 3 lỗi mà 107 test xanh + mypy sạch + 3 vòng
# review đều KHÔNG thấy. Cả ba chỉ lộ ra khi có gói tin thật / tiến trình thật /
# pixel thật:
#
#   1. `TogetherClient` gọi Together bằng `gpt-4o-mini` → 404. Mọi test tiêm fake
#      client, mà fake không quan tâm model id có thật không.
#   2. Model đã ký không tồn tại dạng serverless — có trong /v1/models KÈM bảng
#      giá mà gọi vẫn 400. Danh sách không phải bằng chứng.
#   3. `logger.info` bị uvicorn nuốt (root không handler, mức WARNING). Test xanh
#      vì `caplog.at_level(INFO)` TỰ ÉP mức — nó chứng minh "code có gọi logger",
#      không chứng minh "log tới được production".
#
# Mẫu chung: **test chứng minh code chạy đúng trong môi trường test.** Smoke
# chứng minh hệ thống chạy đúng trong môi trường THẬT. Hai thứ khác nhau, và
# không cái nào thay được cái nào.
#
# Modes:
#   new   <repo> <out.md> [phase]  -> scaffold checklist, tự đoán mặt runtime từ diff
#   stamp <repo> <out.md>          -> chèn diff_sha256 (SCRIPT tính, không tin lời khai)
#   hash  <repo>                   -> in diff_sha256 hiện tại
#
# Flow — THỨ TỰ QUAN TRỌNG:
#   1. new              → scaffold checklist
#   2. chạy tay, điền OBSERVED (dán output THẬT, không viết "OK")
#   3. ghi `SMOKE: PASS ref=<file>` vào ADP block   ← TRƯỚC bước 4
#   4. stamp            → bind diff_sha256
#   5. adp-checkpoint.sh
#
# Bước 3 phải đứng TRƯỚC bước 4: `diff_sha256` băm `git diff HEAD`, mà ghi dòng
# SMOKE vào spec CHÍNH LÀ một thay đổi trong diff đó. Stamp trước rồi mới ghi dòng
# ⇒ hash lệch ⇒ checkpoint REFUSE. (Đúng cái bẫy đã dính với REVIEW ở spec 06 F1;
# ghi ra đây để không phải học lại lần thứ ba.)
#
# Phase không có mặt runtime: KHÔNG cần file này. Ghi thẳng vào block:
#       SMOKE: N/A <lý do cụ thể>
# =============================================================================
set -uo pipefail

_ADPTD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$_ADPTD/../hooks/adp-lib.sh"
[ -f "$LIB" ] || { echo "FATAL: adp-lib.sh not found at $LIB" >&2; exit 1; }
# shellcheck source=../hooks/adp-lib.sh
source "$LIB"

mode="${1:-}"; repo="${2:-}"
[ -n "$mode" ] && [ -n "$repo" ] || { echo "usage: adp-smoke.sh {new|stamp|hash} <repo> [...]" >&2; exit 2; }

SHA=$(adp_work_diff_sha "$repo")
[ -n "$SHA" ] || { echo "FATAL: '$repo' không phải git repo (cần để hash diff)." >&2; exit 1; }
TS=$(date +%Y-%m-%dT%H:%M)

# Đoán mặt runtime từ diff — chỉ để GỢI Ý mục cần kiểm, KHÔNG dùng để quyết định
# có bắt buộc smoke hay không. Đoán sai theo hướng thiếu thì người vẫn phải tự nghĩ;
# nếu để nó quyết định thì một lần đoán sai = một lần bỏ qua âm thầm.
changed=$(cd "$repo" && git diff --name-only HEAD 2>/dev/null; cd "$repo" && git status --porcelain 2>/dev/null | awk '{print $NF}')
has() { printf '%s\n' "$changed" | grep -qE "$1"; }

case "$mode" in
hash) echo "$SHA" ;;

new)
    out="${3:-}"; phase="${4:-?}"
    [ -n "$out" ] || { echo "FATAL: thiếu output path." >&2; exit 1; }
    mkdir -p "$(dirname "$out")"

    {
        echo "# SMOKE — phase ${phase} ($(basename "$repo"))"
        echo
        echo "- generated: ${TS}"
        echo "- diff_sha256: (chưa stamp — chạy \`adp-smoke.sh stamp\` sau khi điền)"
        echo
        echo "> Điền **OBSERVED** bằng output THẬT (dán vào), không viết \"OK\"/\"chạy tốt\"."
        echo "> Một dòng \"OK\" không phân biệt được với việc chưa chạy."
        echo
        echo "## Mặt runtime phát hiện trong diff"
        printf '%s\n' "$changed" | grep -vE '^$' | sed 's/^/- /' | head -20
        echo
        echo "## Checklist"
        echo

        if has '^(agent/providers/|bridge/)'; then
            echo "### [ ] R1 — Gọi provider ngoài THẬT (không fake)"
            echo "Vì sao: fake client không quan tâm model id/endpoint có tồn tại không."
            echo '```'
            echo "# vd: pytest tests/test_together_live.py -m live"
            echo '```'
            echo "OBSERVED:"
            echo '```'
            echo '(dán output)'
            echo '```'
            echo
        fi

        if has '^(api/|app/main\.py)'; then
            echo "### [ ] R2 — Endpoint trên SERVER THẬT (không TestClient)"
            echo "Vì sao: TestClient bỏ qua thứ tự mount thật, middleware, và cấu hình logging."
            echo '```'
            echo "# preview_start ohana-api → gọi endpoint → xem status"
            echo '```'
            echo "OBSERVED (status + body rút gọn):"
            echo '```'
            echo '(dán)'
            echo '```'
            echo
            echo "### [ ] R3 — Log quan sát được XUẤT HIỆN trong log server"
            echo "Vì sao: \`caplog\` tự ép mức log; production thì không. Đây đúng defect 2026-07-19."
            echo "OBSERVED (dán dòng log thật):"
            echo '```'
            echo '(dán)'
            echo '```'
            echo
            echo "### [ ] R4 — Rò tenant: gửi \`shop_id\` giả trong body, grep log"
            echo "Kỳ vọng: log mang shop_id từ JWT; giá trị giả KHÔNG xuất hiện ở đâu."
            echo "OBSERVED:"
            echo '```'
            echo '(dán)'
            echo '```'
            echo
        fi

        if has '^web/'; then
            echo "### [ ] R5 — Render thật trong trình duyệt + chụp màn hình"
            echo "Vì sao: không test nào trong repo thấy layout. Hai lỗi layout G2 (ô nhập bị"
            echo "bóp còn một sợi; ô nhập bị đẩy khỏi màn hình) chỉ lộ khi NHÌN."
            echo "- [ ] desktop"
            echo "- [ ] mobile 375×812 — nội dung dài có đẩy control ra ngoài không?"
            echo "- [ ] console 0 lỗi"
            echo "OBSERVED:"
            echo '```'
            echo '(dán / mô tả ảnh chụp)'
            echo '```'
            echo
        fi

        if has '^db/'; then
            echo "### [ ] R6 — Migration up→down→up trên Postgres THẬT"
            echo "OBSERVED:"
            echo '```'
            echo '(dán)'
            echo '```'
            echo
        fi

        echo "### [ ] R0 — Có gì bất ngờ không?"
        echo "Thứ khiến anh phải nhìn hai lần, dù test xanh. Không có thì ghi \"không\"."
        echo
        echo "OBSERVED:"
        echo '```'
        echo '(dán)'
        echo '```'
        echo
        echo "---"
        echo "SMOKED_BY: "
        echo "VERDICT: (PASS | FAIL — FAIL thì đừng stamp, đi sửa trước)"
    } > "$out"

    echo "scaffolded: $out"
    echo "→ chạy tay, điền OBSERVED bằng output thật, rồi: bash .claude/tools/adp-smoke.sh stamp \"$repo\" $out"
    ;;

stamp)
    out="${3:-}"
    [ -f "$out" ] || { echo "FATAL: '$out' không tồn tại (chạy 'new' trước)." >&2; exit 1; }

    # Từ chối stamp một artifact rỗng. Nếu không chặn, "chạy tay" sẽ thoái hoá thành
    # scaffold-rồi-stamp — tức là một con dấu cao su có hash, tệ hơn không có gì vì
    # nó trông như bằng chứng.
    if grep -qE '^\(dán\)?$|^\(dán output\)$|^\(dán / mô tả ảnh chụp\)$' "$out"; then
        echo "REFUSED — '$out' còn placeholder '(dán…)' chưa điền. Smoke chưa chạy thật thì" >&2
        echo "         stamp chỉ tạo ra con dấu cao su có hash. Điền OBSERVED rồi stamp lại." >&2
        exit 1
    fi
    if ! grep -qE '^SMOKED_BY:[[:space:]]*[^[:space:]]' "$out"; then
        echo "REFUSED — '$out' thiếu SMOKED_BY (ai chạy?)." >&2; exit 1
    fi
    if ! grep -qE '^VERDICT:[[:space:]]*PASS' "$out"; then
        echo "REFUSED — '$out' VERDICT chưa PASS. FAIL thì sửa trước, đừng stamp." >&2; exit 1
    fi

    python3 - "$out" "$SHA" "$TS" <<'PY' || { echo "FATAL: stamp lỗi." >&2; exit 1; }
import sys, re
path, sha, ts = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding="utf-8").read()
s = re.sub(r"^- diff_sha256:.*$", f"- diff_sha256: {sha}", s, count=1, flags=re.M)
if "- diff_sha256:" not in s:
    s = s.replace("\n", f"\n- diff_sha256: {sha}\n", 1)
s = re.sub(r"^- stamped_at:.*\n", "", s, flags=re.M)
s = s.replace(f"- diff_sha256: {sha}", f"- diff_sha256: {sha}\n- stamped_at: {ts}", 1)
open(path, "w", encoding="utf-8").write(s)
print(f"stamped: {path} | diff: {sha[:12]}")
PY
    ;;

*) echo "FATAL: mode '$mode' không hợp lệ (new|stamp|hash)." >&2; exit 2 ;;
esac
