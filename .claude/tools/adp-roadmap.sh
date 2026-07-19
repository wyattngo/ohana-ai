#!/usr/bin/env bash
# adp-roadmap.sh — sinh L3 (docs/ROADMAP-STATUS.md) từ L1 × L2 × git.
#
# L1 = docs/ROADMAP.md §4  (ID + class, do người viết, KHÔNG có status)
# L2 = docs/tasks/*.md     (ADP phase block, trường `ROADMAP: <id>`)
# L3 = file sinh ra        (coverage + uncovered + unplanned) — ĐỪNG sửa tay
#
# Không đọc file này để biết "xong chưa" — nó chỉ phản chiếu L2.
# Một item DONE khi MỌI phase trỏ về nó đều DONE. Không phase nào ⇒ uncovered.
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
L1="$ROOT/docs/ROADMAP.md"
SPECDIR="$ROOT/docs/tasks"
OUT="$ROOT/docs/ROADMAP-STATUS.md"
LEDGER="$ROOT/docs/.roadmap-denominator.log"

[ -f "$L1" ] || { echo "FATAL: thiếu L1 $L1" >&2; exit 1; }
[ -d "$SPECDIR" ] || { echo "FATAL: thiếu SPEC_DIR $SPECDIR" >&2; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---------- 1. L1: ID + class ----------
# Hàng work-item bắt đầu bằng | `GDx-...` | ; class = internal|external (có thể in đậm)
awk -F'|' '
  /^\| `GD[0-9A-Z-]+` \|/ {
    id=$2; gsub(/[` ]/,"",id)
    cls="internal"
    if (tolower($0) ~ /\*\*external\*\*|\| *external *\|/) cls="external"
    print id "\t" cls
  }
' "$L1" | sort -u > "$TMP/l1"

# ---------- 2. L2: phase → (roadmap_id, status) ----------
: > "$TMP/l2"
for f in "$SPECDIR"/*.md; do
  [ -f "$f" ] || continue
  grep -q 'ADP:PHASE' "$f" 2>/dev/null || continue
  awk -v spec="$(basename "$f")" '
    /<!-- ADP:PHASE/ { inb=1; ph=$0; sub(/.*ADP:PHASE[ ]*/,"",ph); sub(/[ ]*-->.*/,"",ph);
                       st=""; rid=""; ev=0; next }
    inb && /^STATUS:/   { st=$2 }
    inb && /^ROADMAP:/  { rid=$2 }
    inb && /^EVIDENCE:/ { ev=1 }
    inb && /<!-- \/ADP/ {
        if (rid=="") rid="(none)"
        if (st=="DONE" && ev==0) st="DONE_NO_EVIDENCE"
        print rid "\t" st "\t" spec "\t" ph
        inb=0
    }
  ' "$f" >> "$TMP/l2"
done

# ---------- 3. join ----------
render_group() {  # $1 = class
  local cls="$1" any=0
  while IFS=$'\t' read -r id c; do
    [ "$c" = "$cls" ] || continue
    local tot done blocked state phases
    tot=$(awk -F'\t' -v i="$id" '$1==i' "$TMP/l2" | wc -l | tr -d ' ')
    done=$(awk -F'\t' -v i="$id" '$1==i && $2=="DONE"' "$TMP/l2" | wc -l | tr -d ' ')
    blocked=$(awk -F'\t' -v i="$id" '$1==i && $2=="BLOCKED"' "$TMP/l2" | wc -l | tr -d ' ')
    phases=$(awk -F'\t' -v i="$id" '$1==i {printf "%s:%s ", substr($3,1,2), $4}' "$TMP/l2")
    if   [ "$tot" -eq 0 ];            then state="⚪ chưa có spec"
    elif [ "$done" -eq "$tot" ];      then state="✅ DONE"
    elif [ "$blocked" -gt 0 ];        then state="⛔ BLOCKED"
    elif [ "$done" -gt 0 ];           then state="🔶 một phần"
    else                                   state="⬜ TODO"
    fi
    printf '| `%s` | %s | %s/%s | %s |\n' "$id" "$state" "$done" "$tot" "${phases:-—}"
    any=1
  done < "$TMP/l1"
  [ "$any" -eq 1 ] || echo '| — | — | — | — |'
}

count_state() {  # $1=class  -> "done total"
  local cls="$1" d=0 t=0
  while IFS=$'\t' read -r id c; do
    [ "$c" = "$cls" ] || continue
    t=$((t+1))
    local tot dn
    tot=$(awk -F'\t' -v i="$id" '$1==i' "$TMP/l2" | wc -l | tr -d ' ')
    dn=$(awk -F'\t' -v i="$id" '$1==i && $2=="DONE"' "$TMP/l2" | wc -l | tr -d ' ')
    [ "$tot" -gt 0 ] && [ "$dn" -eq "$tot" ] && d=$((d+1))
  done < "$TMP/l1"
  echo "$d $t"
}

read -r INT_D INT_T <<< "$(count_state internal)"
read -r EXT_D EXT_T <<< "$(count_state external)"
INT_PCT=0; [ "$INT_T" -gt 0 ] && INT_PCT=$(( INT_D * 100 / INT_T ))
EXT_PCT=0; [ "$EXT_T" -gt 0 ] && EXT_PCT=$(( EXT_D * 100 / EXT_T ))

PH_TOT=$(wc -l < "$TMP/l2" | tr -d ' ')
PH_DONE=$(awk -F'\t' '$2=="DONE"' "$TMP/l2" | wc -l | tr -d ' ')

# uncovered = ID trong L1 mà không phase nào trỏ tới
UNCOV=$(while IFS=$'\t' read -r id c; do
    n=$(awk -F'\t' -v i="$id" '$1==i' "$TMP/l2" | wc -l | tr -d ' ')
    [ "$n" -eq 0 ] && echo "- \`$id\` ($c)"
  done < "$TMP/l1")

# unplanned = phase trỏ tới ID không có trong L1 (hoặc thiếu khoá nối)
UNPLAN=$(awk -F'\t' 'NR==FNR{known[$1]=1; next} !($1 in known){printf "- `%s` ← %s phase %s\n", $1, $3, $4}' \
    "$TMP/l1" "$TMP/l2")

NOEV=$(awk -F'\t' '$2=="DONE_NO_EVIDENCE"{printf "- %s phase %s (khai DONE, thiếu EVIDENCE)\n", $3, $4}' "$TMP/l2")

# ---------- 4. lịch sử mẫu số (chống gian lận chỉ số) ----------
STAMP=$(date +%Y-%m-%dT%H:%M)
LAST=$(tail -1 "$LEDGER" 2>/dev/null | awk '{print $2}')
if [ "$LAST" != "$INT_T" ]; then
  echo "$STAMP $INT_T internal_denominator" >> "$LEDGER"
  if [ -n "$LAST" ] && [ "$INT_T" -lt "$LAST" ]; then
    DENOM_WARN="⚠️ **MẪU SỐ GIẢM** ${LAST} → ${INT_T}. Mẫu số internal giảm mà không có DEC kèm theo là tín hiệu gian lận chỉ số, KHÔNG phải tiến bộ (L1 §0.2)."
  fi
fi
DENOM_HIST=$(tail -5 "$LEDGER" 2>/dev/null | sed 's/^/- /')

# ---------- 5. giữ NOTES_HUMAN ----------
NOTES=""
[ -f "$OUT" ] && NOTES=$(awk '/<!-- NOTES_HUMAN/{f=1; next} f' "$OUT")

# ---------- 6. render ----------
{
cat <<EOF
# ROADMAP STATUS — ohana-ai (L3, SINH MÁY)

> **AUTO-GENERATED bởi \`.claude/tools/adp-roadmap.sh\` @ ${STAMP}.**
> Đây là VIEW join từ L1 (\`docs/ROADMAP.md\`) × L2 (\`docs/tasks/*.md\`) × git — **KHÔNG phải source of truth**.
> ĐỪNG sửa tay phía trên \`NOTES_HUMAN\`. Muốn đổi kế hoạch → sửa L1. Muốn đổi trạng thái → chạy \`adp-checkpoint.sh\`.

## Mục tiêu 100%

**Internal: ${INT_D}/${INT_T} work item hoàn tất (${INT_PCT}%)** ← đây là mẫu số của "100% Roadmap"
External: ${EXT_D}/${EXT_T} (${EXT_PCT}%) — chờ bên thứ ba, **không tính vào 100%**
Phase gate-passed: ${PH_DONE}/${PH_TOT}

${DENOM_WARN:-}

## GĐ0 → GĐ3 — internal (đếm vào 100%)

| Roadmap ID | Trạng thái | Phase done | Phase trỏ tới |
|---|---|---|---|
$(render_group internal)

## External — chờ bên thứ ba (đếm riêng)

| Roadmap ID | Trạng thái | Phase done | Phase trỏ tới |
|---|---|---|---|
$(render_group external)

## ⚠️ Uncovered — mục L1 chưa spec nào nhận

$( [ -n "$UNCOV" ] && echo "$UNCOV" || echo "_(không có — mọi mục roadmap đều có phase)_" )

## ⚠️ Unplanned — phase không trỏ về roadmap nào

Phase ở đây là **scope drift**: đang làm việc không nằm trong kế hoạch, hoặc thiếu khoá nối \`ROADMAP:\`.

$( [ -n "$UNPLAN" ] && echo "$UNPLAN" || echo "_(không có — mọi phase đều có khoá nối hợp lệ)_" )

$( [ -n "$NOEV" ] && printf '## ⚠️ DONE thiếu EVIDENCE\n\n%s\n' "$NOEV" )

## Lịch sử mẫu số internal

$( [ -n "$DENOM_HIST" ] && echo "$DENOM_HIST" || echo "- (chưa có)" )

<!-- NOTES_HUMAN — phần dưới đây generator KHÔNG ghi đè -->
EOF
[ -n "$NOTES" ] && printf '%s\n' "$NOTES"
} > "$OUT"

echo "✅ $OUT"
echo "   internal ${INT_D}/${INT_T} (${INT_PCT}%) · external ${EXT_D}/${EXT_T} · phase ${PH_DONE}/${PH_TOT}"
[ -n "${DENOM_WARN:-}" ] && echo "   $DENOM_WARN"
exit 0
