#!/bin/bash
# ============================================================
# ADP lib — shared parsing for ADP manifest + spec phase blocks
# Sourced by: pre-edit-guard.sh, stop-gate.sh, session-start-context.sh
# Formats defined in: docs/guides/adp-protocol.md
# All functions are read-only and must never exit the caller.
# ============================================================

# Find nearest dir (from $1 upward) whose CLAUDE.md contains an ADP manifest marker.
# Echoes the dir; returns 1 if none found.
adp_find_root() {
    local dir="$1"
    while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "$HOME" ]; do
        if [ -f "$dir/CLAUDE.md" ] && grep -q 'ADP:MANIFEST' "$dir/CLAUDE.md" 2>/dev/null; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

# adp_find_root_or_scan <start_dir> — như adp_find_root, nhưng khi walk-up fail
# (vd session mở ở workspace root), quét các thư mục con TRỰC TIẾP có manifest
# và trả về project ĐANG có phase IN_PROGRESS (lưới an toàn cho Cowork root
# session). Không project nào active → return 1. Nhiều project active cùng lúc
# (vi phạm tinh thần 1-sprint-1-session) → lấy project đầu theo thứ tự tên.
adp_find_root_or_scan() {
    local start="$1" d sd
    if adp_find_root "$start"; then
        return 0
    fi
    for d in "$start"/*/; do
        d="${d%/}"
        [ -f "$d/CLAUDE.md" ] || continue
        grep -q 'ADP:MANIFEST' "$d/CLAUDE.md" 2>/dev/null || continue
        sd=$(adp_manifest_get "$d" SPEC_DIR)
        sd=${sd:-docs/tasks}
        if adp_active_block "$d" "$sd" >/dev/null 2>&1; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

# adp_manifest_get <project_root> <KEY> — echo value of KEY inside the manifest block.
adp_manifest_get() {
    awk -v key="$2" '
        /<!-- ADP:MANIFEST -->/ { inb = 1; next }
        /<!-- \/ADP -->/        { inb = 0 }
        inb && index($0, key ":") == 1 {
            sub("^" key ":[ ]*", "")
            print
            exit
        }' "$1/CLAUDE.md" 2>/dev/null
}

# adp_active_block <project_root> <spec_dir> — print the first phase block with
# STATUS: IN_PROGRESS found in spec_dir, prefixed with a SPEC_FILE: line.
# Returns 1 if no active block.
adp_active_block() {
    local root="$1" spec_dir="$2" f block
    for f in "$root/$spec_dir"/*.md; do
        [ -f "$f" ] || continue
        grep -q 'ADP:PHASE' "$f" 2>/dev/null || continue
        block=$(awk '
            /<!-- ADP:PHASE/ { buf = $0 "\n"; inb = 1; next }
            inb              { buf = buf $0 "\n" }
            /<!-- \/ADP -->/ {
                if (inb) {
                    inb = 0
                    if (buf ~ /STATUS:[ ]*IN_PROGRESS/) { printf "%s", buf; exit }
                }
            }' "$f" 2>/dev/null)
        if [ -n "$block" ]; then
            echo "SPEC_FILE: $f"
            printf '%s\n' "$block"
            return 0
        fi
    done
    return 1
}

# adp_block_get <KEY> — read a block on stdin, echo value of first "KEY:" line.
# Always returns 0 (missing key = empty output) — safe under callers' set -e.
adp_block_get() {
    { grep -m1 "^$1:" || true; } | sed "s/^$1:[ ]*//"
    return 0
}

# adp_last_done_block <project_root> <spec_dir> — print the LAST phase block with
# STATUS: DONE. Prefers the spec file that holds the IN_PROGRESS block (same sprint);
# falls back to scanning all spec files. SPEC_FILE: prefix line. Returns 1 if none.
adp_last_done_block() {
    local root="$1" spec_dir="$2" f block
    local files=()
    # Prefer the active spec file first, then the rest
    local active
    active=$(adp_active_block "$root" "$spec_dir" 2>/dev/null | adp_block_get SPEC_FILE) || active=""
    if [ -n "$active" ]; then files+=("$active"); fi
    for f in "$root/$spec_dir"/*.md; do
        [ -f "$f" ] || continue
        [ "$f" = "$active" ] && continue
        files+=("$f")
    done
    for f in "${files[@]}"; do
        grep -q 'ADP:PHASE' "$f" 2>/dev/null || continue
        block=$(awk '
            /<!-- ADP:PHASE/ { buf = $0 "\n"; inb = 1; next }
            inb              { buf = buf $0 "\n" }
            /<!-- \/ADP -->/ { if (inb) { inb = 0; if (buf ~ /STATUS:[ ]*DONE/) last = buf } }
            END { printf "%s", last }' "$f" 2>/dev/null)
        if [ -n "$block" ]; then
            echo "SPEC_FILE: $f"
            printf '%s\n' "$block"
            return 0
        fi
    done
    return 1
}

# adp_block_gate_full — read a block on stdin, echo GATE_FULL if present, else GATE.
# Always returns 0 — safe under callers' set -e.
adp_block_gate_full() {
    local blk gate_full
    blk=$(cat)
    gate_full=$(printf '%s\n' "$blk" | adp_block_get GATE_FULL) || gate_full=""
    if [ -n "$gate_full" ]; then
        printf '%s\n' "$gate_full"
    else
        printf '%s\n' "$blk" | adp_block_get GATE
    fi
    return 0
}

# adp_state_hash <project_root> <spec_dir> — 12-char fingerprint of the project's
# ADP state: all STATUS/EVIDENCE lines + debt registry + CLAUDE.md position pointer.
# Detects state changed outside a checkpoint (silent drift). Deterministic ordering.
adp_state_hash() {
    local root="$1" spec_dir="$2" f
    {
        for f in "$root/$spec_dir"/*.md; do
            [ -f "$f" ] || continue
            grep -h '^STATUS:\|^EVIDENCE:' "$f" 2>/dev/null || true
        done
        if [ -f "$root/docs/memory/KNOWN_ISSUES.md" ]; then cat "$root/docs/memory/KNOWN_ISSUES.md" 2>/dev/null; fi
        grep -i 'where are we' "$root/CLAUDE.md" 2>/dev/null || true
    } | shasum -a 256 2>/dev/null | cut -c1-12
    return 0
}

# adp_risk_tier <risk_value> — normalize a RISK field value to the v1.3 enum.
# Echoes: high | medium | low. Legacy mapping: money-path→high, none→low.
# Unknown/empty → high: autonomy is NEVER granted on missing data.
# Always returns 0 — safe under callers' set -e.
adp_risk_tier() {
    local v
    v=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    case "$v" in
        low*|none*)        echo "low" ;;
        medium*)           echo "medium" ;;
        high*|money-path*) echo "high" ;;
        *)                 echo "high" ;;
    esac
    return 0
}

# adp_allowed_risk_overlap <allowed_csv> <risk_paths_csv> — floor rule (v1.3).
# Echoes the first ALLOWED_FILES entry that matches RISK_PATHS (substring) and
# returns 0; returns 1 when no overlap. Overlap ⇒ tier floor is "medium".
# CASE-INSENSITIVE (task_f1f2063f, 2026-06-18): money-files are CapCase (Wallet.php)
# but RISK_PATHS are lowercase (wallet) — a case-sensitive match would UNDER-FLAG a
# money-file and let it slip the floor. Folding lives HERE (the canonical money-overlap
# fn) so EVERY call-site is covered: checkpoint floor-rule, session-start warn,
# progress-guard financial-STOP. Comparison folds both sides; the ORIGINAL-case item is
# echoed (so refuse/warn messages still read naturally). NOTE: do NOT push folding into
# adp_path_match — that also backs adp_task_diff_in_scope (exact file-scope), where
# case-sensitivity is correct on case-sensitive filesystems.
adp_allowed_risk_overlap() {
    local allowed="$1" risk="$2" item item_lc risk_lc
    risk_lc=$(printf '%s' "$risk" | tr '[:upper:]' '[:lower:]')
    local OLDIFS="$IFS"
    IFS=','
    for item in $allowed; do
        IFS="$OLDIFS"
        item=$(printf '%s' "$item" | sed 's/^[ ]*//;s/[ ]*$//')
        [ -z "$item" ] && continue
        item_lc=$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]')
        if adp_path_match "$item_lc" "$risk_lc" substr; then
            echo "$item"        # original case preserved for display
            return 0
        fi
        IFS=','
    done
    IFS="$OLDIFS"
    return 1
}

# adp_path_match <rel_path> <csv_list> <mode> — mode "exact" matches entry as
# exact path or prefix (dirs); mode "substr" matches entry anywhere in the path.
# Returns 0 on match.
adp_path_match() {
    local rel="$1" list="$2" mode="$3" item
    local OLDIFS="$IFS"
    IFS=','
    for item in $list; do
        IFS="$OLDIFS"
        item=$(printf '%s' "$item" | sed 's/^[ ]*//;s/[ ]*$//')
        [ -z "$item" ] && continue
        if [ "$mode" = "substr" ]; then
            case "$rel" in *"$item"*) return 0 ;; esac
        else
            case "$rel" in "$item" | "$item"*) return 0 ;; esac
        fi
        IFS=','
    done
    IFS="$OLDIFS"
    return 1
}

# adp_work_diff_sha <repo_root> — sha256 canonical của working diff (git diff HEAD).
# Dùng CHUNG ở review-time (adp-review.sh) và checkpoint-time để 2 đầu hash giống hệt.
# Echo 64-hex; rỗng nếu không phải git repo. Read-only, không exit caller.
adp_work_diff_sha() {
    git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo ""; return 0; }
    git -C "$1" --no-pager diff HEAD 2>/dev/null | shasum -a 256 2>/dev/null | awk '{print $1}'
    return 0
}

# adp_artifact_field <json_file> <field> — echo top-level field (string/number); rỗng nếu thiếu.
adp_artifact_field() {
    python3 - "$1" "$2" <<'PY' 2>/dev/null || true
import sys, json
try:
    v = json.load(open(sys.argv[1])).get(sys.argv[2])
    if v is None:
        pass
    elif isinstance(v, str):
        print(v)
    else:
        print(json.dumps(v))
except Exception:
    pass
PY
    return 0
}

# adp_audit_event <root> <k=v>... — append 1 JSON line vào <root>/docs/.adp-audit.jsonl.
# Audit trail append-only của REVIEW gate decisions (diff_hash, verdict, model, ts, outcome).
# Read-only-safe: KHÔNG bao giờ exit/fail caller, nuốt mọi lỗi.
adp_audit_event() {
    local root="$1"; shift
    [ -n "$root" ] || return 0
    mkdir -p "$root/docs" 2>/dev/null || return 0
    python3 - "$root/docs/.adp-audit.jsonl" "$@" <<'PY' 2>/dev/null || true
import sys, json, datetime
f = sys.argv[1]
obj = {"ts": datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")}
for kv in sys.argv[2:]:
    k, _, v = kv.partition("=")
    obj[k] = v
with open(f, "a") as fh:
    fh.write(json.dumps(obj, ensure_ascii=False) + "\n")
PY
    return 0
}

# ============================================================
# ADP v2 P2 — exec-substrate: handoff schema + validator (E1, KEYSTONE),
# single-writer exec-state (fix #2/#3), cwd git-guard (FIX H),
# frozen sprint-spec lock (E10), per-project profile reader (E11).
# Read-only-safe convention: validators signal via RETURN CODE (rc1) but
# NEVER `exit` the caller. Substrate only — live hook wiring is P3/P4/P5.
# ============================================================

# adp_handoff_schema — canonical micro-task handoff schema version string.
adp_handoff_schema() { echo "adp-handoff/v1"; return 0; }

# adp_handoff_validate <json_file> — validate a micro-task handoff against
# adp-handoff/v1. Required: schema(==adp-handoff/v1), task_id, current_agent,
# files(non-empty array — the per-task diff scope, FIX C), acceptance_cmd,
# risk_tier(high|medium|low), parent_phase, blast(blast-radius, E1 seam for E3/E7).
# Echo "OK"+rc0 if valid; else echo first problem
# (NOFILE | PARSE_ERR | BADSCHEMA:<got> | MISSING:<field> | NOTARRAY:files |
# EMPTY:files | BADRISK:<got>) + rc1. Does NOT exit caller.
adp_handoff_validate() {
    local f="$1"
    [ -f "$f" ] || { echo "NOFILE"; return 1; }
    python3 - "$f" <<'PY'
import sys, json
REQ = ["schema","task_id","current_agent","files","acceptance_cmd",
       "risk_tier","parent_phase","blast"]
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("PARSE_ERR"); sys.exit(1)
if not isinstance(d, dict):
    print("PARSE_ERR"); sys.exit(1)
if d.get("schema") != "adp-handoff/v1":
    print("BADSCHEMA:%s" % d.get("schema")); sys.exit(1)
for k in REQ:                       # presence (key absent)
    if k not in d:
        print("MISSING:%s" % k); sys.exit(1)
if not isinstance(d["files"], list):
    print("NOTARRAY:files"); sys.exit(1)
if not d["files"]:                  # present but empty list
    print("EMPTY:files"); sys.exit(1)
for k in REQ:                       # scalar fields present but empty
    if k == "files":
        continue
    if d[k] in (None, ""):
        print("MISSING:%s" % k); sys.exit(1)
if d["risk_tier"] not in ("high", "medium", "low"):
    print("BADRISK:%s" % d["risk_tier"]); sys.exit(1)
print("OK"); sys.exit(0)
PY
}

# adp_assert_git_repo <dir> — rc0 if dir is inside a git work tree, else rc1.
# FIX H guard: every exec-loop spawn MUST cwd into a git repo, else diff-binding
# (adp_task_diff_sha / adp_work_diff_sha) returns empty → silent gate bypass.
adp_assert_git_repo() {
    git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# adp_exec_state_path <repo_root> — canonical path of the live exec-state file.
adp_exec_state_path() { echo "$1/docs/.adp-exec-state.json"; return 0; }

# adp_exec_state_write <repo_root> <handoff_json> — SINGLE-WRITER entrypoint that
# MAIN calls BEFORE spawning a subagent (fix #2/#3: main records current_agent +
# task_id so SubagentStop/PreToolUse hooks bind verdict to the right task).
# Refuse-spawn semantics: validates handoff (E1) AND asserts repo_root is git
# (FIX H). On success installs handoff atomically as exec-state, echo "OK"+rc0.
# On failure echo reason + rc1 — caller (main) MUST NOT spawn.
adp_exec_state_write() {
    local root="$1" hand="$2" reason dest tmp
    reason=$(adp_handoff_validate "$hand") || { echo "INVALID_HANDOFF:$reason"; return 1; }
    adp_assert_git_repo "$root" || { echo "CWD_NOT_GIT:$root"; return 1; }
    dest=$(adp_exec_state_path "$root")
    mkdir -p "$(dirname "$dest")" 2>/dev/null || { echo "MKDIR_FAIL"; return 1; }
    tmp="$dest.tmp.$$"
    if cp "$hand" "$tmp" 2>/dev/null && mv "$tmp" "$dest" 2>/dev/null; then
        echo "OK"; return 0
    fi
    rm -f "$tmp" 2>/dev/null
    echo "WRITE_FAIL"; return 1
}

# adp_exec_state_get <repo_root> <field> — read a top-level field from exec-state
# (hooks P3/P4 learn current task_id / current_agent). Read-only, rc0.
adp_exec_state_get() {
    adp_artifact_field "$(adp_exec_state_path "$1")" "$2"
    return 0
}

# adp_spec_lock_path <repo_root> — path of the frozen sprint-spec lock.
adp_spec_lock_path() { echo "$1/docs/.sprint-spec.lock"; return 0; }

# adp_spec_lock_compute <spec_file> — 12-hex hash of the IMMUTABLE spec contract:
# every line EXCEPT per-phase progress fields (STATUS/EVIDENCE/RETRY/REVIEW/SMOKE)
# which change legitimately during execution. E10 change-control: GOAL/APPROACH/GATE/
# ALLOWED_FILES/RISK frozen; flipping STATUS or appending REVIEW: PASS ref=…
# (v1.3 reviewer gate, DEC-019) must NOT break the lock. rc0.
#
# SMOKE excluded for the same reason as REVIEW (added 2026-07-19): it is written
# DURING execution, after the contract was frozen. Without this exclusion the smoke
# gate would deadlock — writing the SMOKE line to satisfy the gate would itself trip
# the spec-lock and refuse the checkpoint.
adp_spec_lock_compute() {
    grep -vE '^(STATUS|EVIDENCE|RETRY|REVIEW|SMOKE):' "$1" 2>/dev/null | shasum -a 256 2>/dev/null | cut -c1-12
    return 0
}

# adp_spec_lock_write <repo_root> <spec_file> — freeze current contract hash to the
# lock. Called once when a sprint spec is APPROVED/frozen. rc0.
adp_spec_lock_write() {
    local lock; lock=$(adp_spec_lock_path "$1")
    mkdir -p "$(dirname "$lock")" 2>/dev/null || return 0
    adp_spec_lock_compute "$2" > "$lock" 2>/dev/null
    return 0
}

# adp_spec_lock_verify <repo_root> <spec_file> — compare current contract hash vs
# frozen lock. rc0 if match OR no lock yet (unfrozen → nothing to verify). rc1 +
# echo "DRIFT:<old>-><new>" if the frozen contract changed mid-sprint (checkpoint
# P8 REFUSES). Read-only.
adp_spec_lock_verify() {
    local lock cur old; lock=$(adp_spec_lock_path "$1")
    [ -f "$lock" ] || return 0
    cur=$(adp_spec_lock_compute "$2")
    old=$(cat "$lock" 2>/dev/null)
    [ "$cur" = "$old" ] && return 0
    echo "DRIFT:$old->$cur"; return 1
}

# adp_profile_path <repo_root> — canonical per-project profile path. Agents whose
# cwd = the project repo (FIX H) read this instead of baking ONFA paths (E11:
# 1 def, behaviour per profile → chống rò ONFA→DrNick).
adp_profile_path() { echo "$1/docs/.adp-project-profile.json"; return 0; }

# adp_profile_get <repo_root> <field> — top-level profile field. rc0, empty if missing.
adp_profile_get() {
    adp_artifact_field "$(adp_profile_path "$1")" "$2"
    return 0
}

# adp_profile_skill <repo_root> <task_kind> — map a task kind (backend/ui/ui_design/
# fullstack/frogverse_backend/frogverse_ui/default) to the project's skill via the
# profile skill_map (falls back to skill_map.default). Echo skill name; empty if
# unmapped. rc0.
adp_profile_skill() {
    python3 - "$(adp_profile_path "$1")" "$2" <<'PY' 2>/dev/null || true
import sys, json
try:
    m = json.load(open(sys.argv[1])).get("skill_map", {})
    v = m.get(sys.argv[2]) or m.get("default", "")
    if v:
        print(v)
except Exception:
    pass
PY
    return 0
}

# ============================================================
# ADP v2.3 P4 — Generic-coder gated mode (kills D3). When a stack has NO canonical
# skill (adp_profile_skill → ""), coder MAY implement directly — but ONLY under the
# default-deny flag `allow_generic` + the floor rule (RISK_PATHS overlap ⇒ STOP).
# These are deterministic-gate helpers; they grant NO new LLM authority.
# ============================================================

# adp_profile_allow_generic <repo_root> — echo "true" iff profile.allow_generic is
# boolean true (JSON true OR string "true"); else "false". DEFAULT DENY (missing/
# unparseable → "false"). rc0, never exits caller.
adp_profile_allow_generic() {
    python3 - "$(adp_profile_path "$1")" <<'PY' 2>/dev/null || { echo "false"; return 0; }
import sys, json
try:
    v = json.load(open(sys.argv[1])).get("allow_generic", False)
except Exception:
    v = False
print("true" if (v is True or str(v).strip().lower() == "true") else "false")
PY
    return 0
}

# adp_coder_mode <repo_root> <task_kind> <files_csv> [ack] — decide coder execution
# mode for a micro-task. Single source of truth for the generic-vs-skill gate, mirrored
# by coder.md. Echo + rc:
#   "skill:<name>"  rc0  — canonical skill exists → UNCHANGED skill path (allow_generic
#                          irrelevant; anti-drift guarantee intact where skills exist).
#   "generic"       rc0  — no skill + allow_generic:true + no RISK_PATHS overlap (or
#                          overlap WITH Wyatt-ack="ack") → gated direct implement.
#   "REFUSE:<why>"  rc1  — no skill + generic disabled (default-deny), OR RISK_PATHS
#                          overlap without ack → STOP + route to Decision Protocol (P3).
# Floor rule preserved: a RISK_PATHS hit never auto-proceeds; it forces a human ack.
adp_coder_mode() {
    local repo="$1" kind="$2" files_csv="${3:-}" ack="${4:-}"
    local skill; skill="$(adp_profile_skill "$repo" "$kind")"
    if [ -n "$skill" ]; then echo "skill:$skill"; return 0; fi
    if [ "$(adp_profile_allow_generic "$repo")" != "true" ]; then
        echo "REFUSE:no-skill-generic-disabled"; return 1
    fi
    local ov; ov="$(adp_risk_overlap_ci "$repo" "$files_csv")"
    if [ -n "$ov" ] && [ "$ack" != "ack" ]; then
        echo "REFUSE:risk-overlap:$ov(need-decision)"; return 1
    fi
    echo "generic"; return 0
}

# ============================================================
# ADP v2.3 P3 — Decision Protocol validator (adp-decision/v1).
# Echo "OK" + rc0 if the file is a conformant 3-option decision; else echo the first
# violation + rc1. Invariants: schema match · EXACTLY 3 options · distinct ids ·
# EXACTLY one recommended:true · each option non-empty title/approach + risk∈{high,
# medium,low} + effort∈{S,M,L}. Read-only, never exits the caller.
adp_decision_validate() {
    python3 - "${1:-}" <<'PY' 2>/dev/null || return 1
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("NOFILE/PARSE_ERR"); sys.exit(1)
def bad(m): print(m); sys.exit(1)
if d.get("schema") != "adp-decision/v1": bad("BADSCHEMA")
opts = d.get("options")
if not isinstance(opts, list): bad("NOTARRAY")
if len(opts) != 3: bad("NOT3OPTIONS")
ids = [o.get("id") for o in opts]
if len(set(ids)) != 3 or any(not i for i in ids): bad("DUP_OR_EMPTY_ID")
rec = sum(1 for o in opts if o.get("recommended") is True)
if rec != 1: bad("NEED_EXACTLY_ONE_RECOMMENDED")
for o in opts:
    if not str(o.get("title") or "").strip() or not str(o.get("approach") or "").strip(): bad("EMPTY_TITLE_OR_APPROACH")
    if o.get("risk") not in ("high","medium","low"): bad("BADRISK")
    if o.get("effort") not in ("S","M","L"): bad("BADEFFORT")
print("OK"); sys.exit(0)
PY
    return 0
}

# ============================================================
# ADP v2 P3 — per-task diff binding (FIX C) + scope guard.
# Sibling of adp_work_diff_sha but SCOPED to a micro-task's declared files, so the
# SubagentStop gate verdict binds to exactly what the task was allowed to touch.
# ============================================================

# adp_task_diff_sha <repo_root> <file>... — sha256 of `git diff HEAD` LIMITED to the
# declared paths of a micro-task (FIX C). Echo 64-hex. Echo EMPTY when non-git, no
# files given, OR the in-scope diff is empty (no-op-diff → caller treats as FAIL,
# fix #5 — NOTE: empty must be distinguished here, else `shasum` of empty input
# yields a non-empty constant hash and the no-op slips through). Read-only, rc0.
adp_task_diff_sha() {
    local root="$1"; shift
    git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo ""; return 0; }
    [ "$#" -gt 0 ] || { echo ""; return 0; }
    local d
    d=$(git -C "$root" --no-pager diff HEAD -- "$@" 2>/dev/null)
    [ -n "$d" ] || { echo ""; return 0; }
    printf '%s' "$d" | shasum -a 256 2>/dev/null | awk '{print $1}'
    return 0
}

# adp_task_diff_in_scope <repo_root> <declared_csv> — FIX C guard: rc0 if EVERY
# changed file (git diff HEAD --name-only) matches a declared path (exact/prefix via
# adp_path_match); rc1 + echo the first out-of-scope file otherwise. Empty diff →
# rc0 (vacuously in scope; no-op is caught separately by adp_task_diff_sha).
# Read-only, never exits caller.
adp_task_diff_in_scope() {
    local root="$1" declared="$2" f
    git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        adp_path_match "$f" "$declared" exact || { echo "$f"; return 1; }
    done < <(git -C "$root" --no-pager diff HEAD --name-only 2>/dev/null)
    return 0
}

# ============================================================
# ADP v2 P6 — RED-proof (TDD ordering) + E7 DoR risk overlap (case-folded).
# "Ai test cái test?" — a test that was NEVER red can't prove it binds to the diff.
# A valid gate-test must FAIL before the code (RED), then PASS after (GREEN), with the
# SAME acceptance_cmd (hash-bound). gate-verdict (P6) REFUSES a GREEN that has no valid
# RED-proof. Read-only-safe: writers never exit caller.
# ============================================================

# adp_cmd_sha <cmd_string> — sha256 of an acceptance_cmd string (hash-bind RED↔GREEN).
adp_cmd_sha() { printf '%s' "$1" | shasum -a 256 2>/dev/null | awk '{print $1}'; return 0; }

# adp_red_proof_path <repo_root> — canonical RED-proof store (keyed by task_id).
adp_red_proof_path() { echo "$1/docs/.adp-red-proof.json"; return 0; }

# adp_red_proof_record <repo> <task_id> <acc_sha> <red_exit> <files_csv> — upsert one
# task's RED-proof {acc_sha, red_exit, red_ts, files}. Only adp-review.sh `red` calls
# this, and ONLY after it has confirmed the cmd actually failed (red_exit != 0). rc0.
adp_red_proof_record() {
    local root="$1" tid="$2" accsha="$3" rexit="$4" files="$5" p
    p=$(adp_red_proof_path "$root")
    mkdir -p "$(dirname "$p")" 2>/dev/null || return 0
    python3 - "$p" "$tid" "$accsha" "$rexit" "$files" <<'PY' 2>/dev/null || true
import sys, json, datetime
p, tid, accsha, rexit, files = sys.argv[1:6]
try:
    d = json.load(open(p))
    if not isinstance(d, dict): d = {}
except Exception:
    d = {}
d[tid] = {"acc_sha": accsha, "red_exit": rexit,
          "red_ts": datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z"),
          "files": files}
open(p, "w").write(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
PY
    return 0
}

# adp_red_proof_get <repo> <task_id> <field> — read acc_sha|red_exit|red_ts|files for a
# task. Echo value; empty if no proof recorded. Read-only, rc0.
adp_red_proof_get() {
    python3 - "$(adp_red_proof_path "$1")" "$2" "$3" <<'PY' 2>/dev/null || true
import sys, json
try:
    v = json.load(open(sys.argv[1])).get(sys.argv[2], {}).get(sys.argv[3])
    if v is not None:
        print(v)
except Exception:
    pass
PY
    return 0
}

# adp_risk_overlap_ci <repo> <files_csv> — CASE-INSENSITIVE overlap of changed files vs
# profile.risk_paths (substr). Echo first matched risk token; empty if none. rc0.
# NOTE: case-folded locally to avoid the case-sensitivity gap in adp_allowed_risk_overlap
# (a CapCase money-file like Wallet.php must match risk token `wallet`). Global
# unification of case-folding across all call sites is tracked separately.
adp_risk_overlap_ci() {
    python3 - "$(adp_profile_path "$1")" "$2" <<'PY' 2>/dev/null || true
import sys, json
try:
    rp = json.load(open(sys.argv[1])).get("risk_paths", [])
except Exception:
    rp = []
files = [f.strip().lower() for f in sys.argv[2].split(",") if f.strip()]
for r in rp:
    rl = str(r).strip().lower()
    if not rl:
        continue
    for f in files:
        if rl in f:
            print(r); sys.exit(0)
PY
    return 0
}
