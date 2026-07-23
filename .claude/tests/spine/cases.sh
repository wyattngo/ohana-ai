# =============================================================================
# SPINE cases — PROJECT-AGNOSTIC (no ONFA/DrNick presence required).
# Sourced by run.sh AND run-spine.sh (after lib.sh). Pass on a relocated bare copy.
# Mechanical extraction (Task#20 P5) — NO logic change vs the old monolithic run.sh.
# =============================================================================
# Test fixtures for secrets-scanner — split literals to bypass GitHub's static
# push-protection scanner while keeping the runtime concatenated string intact
# for the hook's regex. Values are sequential-char fakes, NOT real credentials.
_GH_TOK="ghp""_0123456789abcdefghij0123456789abcdef"
_STRIPE="sk""_live""_0123456789abcdefghijklmn"
_JWT="eyJa.eyJb.cccc"
# ---------------------------------------------------------------------------
echo "[1] output-secrets-scanner.sh"
H="$HOOKS/output-secrets-scanner.sh"
o=$(printf '%s' '{"tool_name":"Read","tool_response":"-----BEGIN RSA PRIVATE KEY-----\nx\n-----END"}' | bash "$H")
has "PEM → warn Private Key" "$o" "Private Key (PEM)"
o=$(printf '%s' '{"tool_name":"Bash","tool_response":"'"${_GH_TOK} ${_STRIPE} ${_JWT}"'"}' | bash "$H")
has "GitHub token detected" "$o" "GitHub Token"
has "Stripe token detected" "$o" "Stripe Key"
o=$(printf '%s' '{"tool_name":"Bash","tool_response":"sha a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0 uuid 550e8400-e29b-41d4-a716-446655440000 password=cfg"}' | bash "$H")
empty "clean (SHA+UUID+code) → no false positive" "$o"
o=$(printf '%s' '{"tool_name":"Bash","result":"'"${_GH_TOK}"'"}' | bash "$H")
has "schema-drift (field result) → blob fallback" "$o" "GitHub Token"
o=$(printf '%s' '{"tool_name":"Read","tool_response":"-----BEGIN OPENSSH PRIVATE KEY-----"}' | OSS_BLOCK_ON_PRIVATE_KEY=1 bash "$H")
has "block mode → decision:block" "$o" '"decision": "block"'
J='{"tool_name":"Bash","tool_response":"apikey=AbCdEf0123456789ghij"}'
o=$(printf '%s' "$J" | bash "$H");                  empty "generic OFF → silent" "$o"
o=$(printf '%s' "$J" | OSS_GENERIC=1 bash "$H");    has   "generic ON → warn"   "$o" "Generic Secret"

# ---------------------------------------------------------------------------
echo "[2] mcp-config-integrity.sh"
M="$HOOKS/mcp-config-integrity.sh"
cat > "$TMP/cfg.json" <<'JSON'
{"mcpServers":{
 "danger":{"command":"npx","args":["-y","--no-sandbox","evil"]},
 "uselatest":{"command":"npx","args":["-y","tool@latest"]},
 "unpinned":{"command":"npx","args":["-y","another-tool"]},
 "secretenv":{"command":"node","args":["x.js"],"env":{"API_KEY":"abcdef1234567890hard"}},
 "good":{"command":"/x/npx","args":["-y","claude-code-ultimate-guide-mcp@1.2.0"]}
}}
JSON
MCP_CFG="$TMP/cfg.json" MCP_BASELINE="$TMP/cfg.base" bash "$M" --init >/dev/null
o=$(MCP_CFG="$TMP/cfg.json" MCP_BASELINE="$TMP/cfg.base" bash "$M")
has  "dangerous flag detected" "$o" "MCP danger:"
has  "@latest detected"        "$o" "MCP uselatest:"
has  "unpinned detected"       "$o" "MCP unpinned:"
has  "hardcoded secret env"    "$o" "MCP secretenv:"
hasnt "pinned-good NOT flagged" "$o" "MCP good:"
echo "deadbeef" > "$TMP/wrong.base"
o=$(MCP_CFG="$TMP/cfg.json" MCP_BASELINE="$TMP/wrong.base" bash "$M")
has  "tamper (baseline mismatch) → warn" "$o" "DOI so voi baseline"
cat > "$TMP/clean.json" <<'JSON'
{"mcpServers":{"good":{"command":"/x/npx","args":["-y","pkg@1.0.0"]}}}
JSON
MCP_CFG="$TMP/clean.json" MCP_BASELINE="$TMP/clean.base" bash "$M" --init >/dev/null
o=$(MCP_CFG="$TMP/clean.json" MCP_BASELINE="$TMP/clean.base" bash "$M")
empty "clean+matching baseline → silent" "$o"

# ---------------------------------------------------------------------------
echo "[3] adp-checkpoint.sh — judge gate"
A="$TOOLS/adp-checkpoint.sh"
sed -n '/^adp_review_verdict()/,/^}$/p'        "$A"  > "$TMP/fns.sh"
sed -n '/^review_validate_artifact()/,/^}$/p'  "$A" >> "$TMP/fns.sh"
# shellcheck source=/dev/null
source "$HOOKS/adp-lib.sh"   # adp_work_diff_sha + adp_artifact_field (P1)
source "$TMP/fns.sh"
printf '{"verdict":"APPROVE"}' > "$TMP/good.json"
printf '{"verdict":"REJECT"}'  > "$TMP/bad.json"
printf 'not-json{{{'           > "$TMP/mal.json"
eq "verdict APPROVE"   "$(adp_review_verdict "$TMP" good.json)" "APPROVE"
eq "verdict REJECT"    "$(adp_review_verdict "$TMP" bad.json)"  "REJECT"
eq "verdict MISSING"   "$(adp_review_verdict "$TMP" nope.json)" "MISSING"
eq "verdict PARSE_ERR" "$(adp_review_verdict "$TMP" mal.json)"  "PARSE_ERR"
( ROOT="$TMP" REVIEW_VAL="PASS ref=$TMP/good.json" REVIEW_REF="$TMP/good.json"; review_validate_artifact medium >/dev/null 2>&1 ) \
  && ok "APPROVE → checkpoint allowed (rc0)" || no "APPROVE rc0" "rc=$?"
( ROOT="$TMP" REVIEW_VAL="PASS ref=$TMP/bad.json" REVIEW_REF="$TMP/bad.json"; review_validate_artifact medium >/dev/null 2>&1 ) \
  && no "REJECT should refuse" "got rc0" || ok "REJECT → refused (rc!=0)"
( ROOT="$TMP" REVIEW_VAL="PASS ref=$TMP/nope.json" REVIEW_REF="$TMP/nope.json"; review_validate_artifact medium >/dev/null 2>&1 ) \
  && no "MISSING should refuse" "got rc0" || ok "MISSING → refused (rc!=0)"
( ROOT="$TMP" REVIEW_VAL="PASS" REVIEW_REF=""; review_validate_artifact medium >/dev/null 2>&1 ) \
  && ok "legacy no-ref → allowed (rc0)" || no "legacy rc0" "rc=$?"

# ---------------------------------------------------------------------------
echo "[4] P1 diff-binding (adp-review.sh + checkpoint)"
RR="$TMP/repo"; mkdir -p "$RR"
( cd "$RR" && git init -q && git config user.email t@t.t && git config user.name t \
   && echo base > f.txt && git add f.txt && git commit -qm init && echo changed >> f.txt ) 2>/dev/null
SHA=$(adp_work_diff_sha "$RR")
[ -n "$SHA" ] && ok "adp_work_diff_sha → hash trên git repo" || no "work_sha" "rỗng"
printf '{"verdict":"APPROVE","model":"haiku","diff_sha256":"FAKE-LLM-CLAIM"}' > "$TMP/vin.json"
bash "$TOOLS/adp-review.sh" stamp "$RR" "$TMP/vin.json" "$TMP/art.json" >/dev/null 2>&1
eq "stamp đè hash LLM tự khai bằng hash thật" "$(adp_artifact_field "$TMP/art.json" diff_sha256)" "$SHA"
( ROOT="$RR" REVIEW_VAL="PASS ref=$TMP/art.json" REVIEW_REF="$TMP/art.json"; review_validate_artifact medium >/dev/null 2>&1 ) \
  && ok "bound match → allowed" || no "bound match" "rc=$?"
( cd "$RR" && echo more >> f.txt ) 2>/dev/null
( ROOT="$RR" REVIEW_VAL="PASS ref=$TMP/art.json" REVIEW_REF="$TMP/art.json"; review_validate_artifact medium >/dev/null 2>&1 ) \
  && no "diff đổi sau review phải refuse" "got rc0" || ok "diff đổi sau review → REFUSED"
bash "$TOOLS/adp-review.sh" stamp "$RR" "$TMP/vin.json" "$TMP/art.json" >/dev/null 2>&1   # re-bind current
( ROOT="$RR" REVIEW_VAL="PASS ref=$TMP/art.json" REVIEW_REF="$TMP/art.json"; review_validate_artifact high >/dev/null 2>&1 ) \
  && no "high thiếu human phải refuse" "got rc0" || ok "high thiếu human= → REFUSED"
bash "$TOOLS/adp-review.sh" human "$RR" "$TMP/hum.md" >/dev/null 2>&1
( ROOT="$RR" REVIEW_VAL="PASS ref=$TMP/art.json human=$TMP/hum.md" REVIEW_REF="$TMP/art.json"; review_validate_artifact high >/dev/null 2>&1 ) \
  && ok "high + human bound&signed → allowed" || no "high+human" "rc=$?"

# ---------------------------------------------------------------------------
echo "[5] P2 audit trail (docs/.adp-audit.jsonl)"
AUD="$RR/docs/.adp-audit.jsonl"
[ -f "$AUD" ] && ok "audit log được tạo" || no "audit log" "không thấy $AUD"
grep -q '"outcome": "PASS"' "$AUD" 2>/dev/null      && ok "PASS event ghi {verdict,diff,model,ts}" || no "PASS event" "thiếu"
grep -q '"outcome": "REFUSED"' "$AUD" 2>/dev/null   && ok "REFUSED event (security block) ghi"     || no "REFUSED event" "thiếu"
grep -q '"reason": "diff-mismatch"' "$AUD" 2>/dev/null && ok "diff-mismatch được audit"             || no "diff-mismatch audit" "thiếu"
python3 -c 'import json,sys; [json.loads(l) for l in open(sys.argv[1]) if l.strip()]' "$AUD" 2>/dev/null \
  && ok "mọi dòng JSONL hợp lệ" || no "jsonl valid" "có dòng hỏng"

# ---------------------------------------------------------------------------
echo "[6] P2/E1 handoff schema + validator (adp-handoff/v1)"
eq "schema version constant" "$(adp_handoff_schema)" "adp-handoff/v1"
cat > "$TMP/h_ok.json" <<'JSON'
{"schema":"adp-handoff/v1","task_id":"P2.t1","current_agent":"coder","files":["a.php"],"acceptance_cmd":"php t.php","risk_tier":"low","parent_phase":"2","blast":"1 file"}
JSON
eq "valid handoff → OK" "$(adp_handoff_validate "$TMP/h_ok.json")" "OK"
adp_handoff_validate "$TMP/h_ok.json" >/dev/null && ok "valid handoff → rc0" || no "valid rc0" "rc=$?"
printf '%s' '{"schema":"adp-handoff/v1","task_id":"x","current_agent":"c","acceptance_cmd":"c","risk_tier":"low","parent_phase":"2","blast":"b"}' > "$TMP/h_miss.json"
has "missing files → MISSING:files" "$(adp_handoff_validate "$TMP/h_miss.json")" "MISSING:files"
adp_handoff_validate "$TMP/h_miss.json" >/dev/null 2>&1 && no "missing should rc1" "got rc0" || ok "missing field → rc1 (refuse-spawn)"
printf '%s' '{"schema":"WRONG","task_id":"x","current_agent":"c","files":["a"],"acceptance_cmd":"c","risk_tier":"low","parent_phase":"2","blast":"b"}' > "$TMP/h_sch.json"
has "bad schema → BADSCHEMA" "$(adp_handoff_validate "$TMP/h_sch.json")" "BADSCHEMA:"
printf '%s' '{"schema":"adp-handoff/v1","task_id":"x","current_agent":"c","files":[],"acceptance_cmd":"c","risk_tier":"low","parent_phase":"2","blast":"b"}' > "$TMP/h_empty.json"
has "empty files array → EMPTY:files" "$(adp_handoff_validate "$TMP/h_empty.json")" "EMPTY:files"
printf '%s' '{"schema":"adp-handoff/v1","task_id":"x","current_agent":"c","files":["a"],"acceptance_cmd":"c","risk_tier":"BOGUS","parent_phase":"2","blast":"b"}' > "$TMP/h_risk.json"
has "bad risk_tier → BADRISK" "$(adp_handoff_validate "$TMP/h_risk.json")" "BADRISK:"
printf '%s' 'not-json{{' > "$TMP/h_mal.json"
has "malformed json → PARSE_ERR" "$(adp_handoff_validate "$TMP/h_mal.json")" "PARSE_ERR"
eq "no file → NOFILE" "$(adp_handoff_validate "$TMP/nope.json")" "NOFILE"

# ---------------------------------------------------------------------------
echo "[7] P2 exec-state single-writer + FIX H cwd-git-guard"
adp_assert_git_repo "$RR" && ok "assert_git_repo on git → rc0" || no "git rc0" "rc=$?"
adp_assert_git_repo "$TMP" && no "assert_git_repo non-git should rc1" "got rc0" || ok "non-git → rc1 (FIX H)"
eq "exec_state_write valid+git → OK" "$(adp_exec_state_write "$RR" "$TMP/h_ok.json")" "OK"
[ -f "$(adp_exec_state_path "$RR")" ] && ok "exec-state file created" || no "exec-state file" "không thấy"
eq "exec_state_get task_id" "$(adp_exec_state_get "$RR" task_id)" "P2.t1"
eq "exec_state_get current_agent" "$(adp_exec_state_get "$RR" current_agent)" "coder"
has "invalid handoff → INVALID_HANDOFF" "$(adp_exec_state_write "$RR" "$TMP/h_miss.json" 2>&1)" "INVALID_HANDOFF"
adp_exec_state_write "$RR" "$TMP/h_miss.json" >/dev/null 2>&1 && no "invalid should rc1" "got rc0" || ok "invalid handoff → rc1 (refuse-spawn)"
has "non-git cwd → CWD_NOT_GIT (FIX H refuse)" "$(adp_exec_state_write "$TMP" "$TMP/h_ok.json" 2>&1)" "CWD_NOT_GIT"

# ---------------------------------------------------------------------------
echo "[8] P2/E10 sprint-spec lock (change-control)"
cat > "$TMP/spec.md" <<'MD'
<!-- ADP:PHASE 0 -->
STATUS: TODO
GOAL: do the thing
GATE: bash run.sh
RISK: low
<!-- /ADP -->
MD
adp_spec_lock_write "$RR" "$TMP/spec.md"
[ -f "$(adp_spec_lock_path "$RR")" ] && ok "spec lock written" || no "lock written" "không thấy"
adp_spec_lock_verify "$RR" "$TMP/spec.md" && ok "unchanged spec → verify rc0" || no "unchanged rc0" "rc=$?"
sed -i.bak 's/STATUS: TODO/STATUS: DONE/' "$TMP/spec.md" && rm -f "$TMP/spec.md.bak"
adp_spec_lock_verify "$RR" "$TMP/spec.md" && ok "flip STATUS only → rc0 (no drift)" || no "status-flip drift" "rc=$?"
sed -i.bak 's/do the thing/do SOMETHING ELSE/' "$TMP/spec.md" && rm -f "$TMP/spec.md.bak"
dout=$(adp_spec_lock_verify "$RR" "$TMP/spec.md" 2>&1) && no "contract change should rc1" "got rc0" || ok "contract change → rc1 (REFUSE)"
has "drift reason emitted" "$dout" "DRIFT:"
RR2="$TMP/repo2"; mkdir -p "$RR2/docs"
adp_spec_lock_verify "$RR2" "$TMP/spec.md" && ok "no lock (unfrozen) → rc0 allow" || no "unfrozen rc0" "rc=$?"

# ---------------------------------------------------------------------------
echo "[10] P3 SubagentStop gate-verdict (SHADOW, diff-bound per-task)"
HGV="$HOOKS/gate-verdict.sh"
GV="$TMP/gv"; mkdir -p "$GV"
( cd "$GV" && git init -q && git config user.email t@t.t && git config user.name t \
   && echo base > a.txt && echo base > b.txt && git add a.txt b.txt && git commit -qm init ) 2>/dev/null
write_state(){ # $1=task_id $2=current_agent $3=acceptance_cmd $4=files_json
  printf '{"schema":"adp-handoff/v1","task_id":"%s","current_agent":"%s","files":%s,"acceptance_cmd":"%s","risk_tier":"low","parent_phase":"3","blast":"t"}' \
    "$1" "$2" "$4" "$3" > "$TMP/hand.json"
  adp_exec_state_write "$GV" "$TMP/hand.json" >/dev/null 2>&1
}
reset_tree(){ ( cd "$GV" && git checkout -- . ) 2>/dev/null; rm -f "$GV/docs/.adp-gate-verdict.json"; }
fire(){ printf '{"cwd":"%s","agent_type":"%s","stop_hook_active":false}' "$GV" "$1" | bash "$HGV"; }
gv_field(){ adp_artifact_field "$GV/docs/.adp-gate-verdict.json" "$1"; }

# adp_task_diff_sha + scope guard (unit)
reset_tree; ( cd "$GV" && echo x >> a.txt )
[ -n "$(adp_task_diff_sha "$GV" a.txt)" ] && ok "task_diff_sha: in-scope change → hash" || no "task_sha hash" "rỗng"
empty "task_diff_sha: no-op (scope=b.txt unchanged) → empty" "$(adp_task_diff_sha "$GV" b.txt)"
adp_task_diff_in_scope "$GV" "a.txt" && ok "in_scope: only declared changed → rc0" || no "in_scope rc0" "rc=$?"
( cd "$GV" && echo y >> b.txt )
oos=$(adp_task_diff_in_scope "$GV" "a.txt") && no "in_scope should rc1" "got rc0" || eq "in_scope: out-of-scope file flagged" "$oos" "b.txt"

# PASS: real RED→GREEN gate-test (P6 — an always-green `true` is no longer a valid gate)
REVIEW="$CLAUDE_DIR/tools/adp-review.sh"
reset_tree                                                       # a.txt = base (no PATCHED)
bash "$REVIEW" red "$GV" P3.t1 'grep -q PATCHED a.txt' a.txt >/dev/null 2>&1   # record RED
( cd "$GV" && echo PATCHED >> a.txt )                           # coder implements (in-scope)
write_state P3.t1 coder 'grep -q PATCHED a.txt' '["a.txt"]'
out=$(fire coder)
has "PASS: shadow continue (never block)" "$out" '"continue": true'
eq  "PASS: cache verdict=PASS (RED→GREEN, red-proof bound)" "$(gv_field verdict)" "PASS"
[ -n "$(gv_field task_diff_sha)" ] && ok "PASS: verdict diff-bound (sha set)" || no "diff-bound" "sha rỗng"
grep -q '"outcome": "PASS"' "$GV/docs/.adp-audit.jsonl" 2>/dev/null && ok "PASS: audit outcome=PASS" || no "audit PASS" "thiếu"

# FAIL: acceptance_cmd non-zero
reset_tree; write_state P3.t2 coder 'exit 3' '["a.txt"]'; ( cd "$GV" && echo c >> a.txt )
out=$(fire coder)
eq  "FAIL: cache verdict=FAIL" "$(gv_field verdict)" "FAIL"
has "FAIL: flag test-exit:3" "$(gv_field flags)" "test-exit:3"
has "FAIL: still shadow continue" "$out" '"continue": true'

# no-op-diff: test green but nothing changed in scope (fix #5)
reset_tree; write_state P3.t3 coder true '["a.txt"]'
fire coder >/dev/null
eq  "no-op-diff: verdict=FAIL" "$(gv_field verdict)" "FAIL"
has "no-op-diff: flagged" "$(gv_field flags)" "no-op-diff"

# out-of-scope: change declared + undeclared file
reset_tree; write_state P3.t4 coder true '["a.txt"]'; ( cd "$GV" && echo c >> a.txt && echo d >> b.txt )
fire coder >/dev/null
eq  "out-of-scope: verdict=FAIL" "$(gv_field verdict)" "FAIL"
has "out-of-scope: flag b.txt" "$(gv_field flags)" "out-of-scope:b.txt"

# agent-mismatch: exec-state coder, SubagentStop bug-fixer
reset_tree; write_state P3.t5 coder true '["a.txt"]'; ( cd "$GV" && echo c >> a.txt )
fire bug-fixer >/dev/null
has "agent-mismatch flagged" "$(gv_field flags)" "agent-mismatch:bug-fixer!=coder"

# not-applicable: no exec-state → shadow passthrough, no crash
rm -f "$GV/docs/.adp-exec-state.json"
has "no exec-state → continue passthrough" "$(fire coder)" '"continue": true'

# ---------------------------------------------------------------------------
echo "[11] P4 PreToolUse breaker + financial gate + canary (SHADOW)"
HPG="$HOOKS/progress-guard.sh"
PG="$TMP/pg"; mkdir -p "$PG/docs"
( cd "$PG" && git init -q && git config user.email t@t.t && git config user.name t \
   && echo x > f.txt && git add f.txt && git commit -qm init ) 2>/dev/null
cat > "$PG/docs/.adp-project-profile.json" <<'JSON'
{"schema":"adp-project-profile/v1","project":"pg","risk_paths":["wallet","commission"],"skill_map":{"default":"x"}}
JSON
pg_state(){ # $1=task_id $2=files_json $3=phase
  printf '{"schema":"adp-handoff/v1","task_id":"%s","current_agent":"coder","files":%s,"acceptance_cmd":"true","risk_tier":"low","parent_phase":"%s","blast":"t"}' \
    "$1" "$2" "$3" > "$TMP/pgh.json"
  adp_exec_state_write "$PG" "$TMP/pgh.json" >/dev/null 2>&1
}
pg_fail(){ printf '{"gate":"gate-verdict","phase":"%s","task":"%s","outcome":"FAIL","task_diff":"%s"}\n' "$1" "$2" "$3" >> "$PG/docs/.adp-audit.jsonl"; }
pg_reset_audit(){ : > "$PG/docs/.adp-audit.jsonl"; }
pg_reset_state(){ rm -f "$PG/docs/.adp-breaker.json"; }
fire_pg(){ printf '{"cwd":"%s","tool_input":{"subagent_type":"%s"}}' "$PG" "$1" | bash "$HPG"; }
pg_field(){ adp_artifact_field "$PG/docs/.adp-breaker.json" "$1"; }

# clean → allow
pg_reset_audit; pg_reset_state; pg_state P4.t1 '["f.txt"]' 4
has "clean → shadow continue" "$(fire_pg coder)" '"continue": true'
eq  "clean → decision allow" "$(pg_field decision)" "allow"

# 3 consecutive FAIL (distinct diffs) → rethink (once)
pg_reset_audit; pg_reset_state; pg_state P4.t2 '["f.txt"]' 4
pg_fail 4 P4.t2 d1; pg_fail 4 P4.t2 d2; pg_fail 4 P4.t2 d3
fire_pg coder >/dev/null
eq "3-fail → decision block (shadow)" "$(pg_field decision)" "block"
eq "3-fail → reason rethink" "$(pg_field reason)" "rethink"

# 5 consecutive FAIL → trip + would-stash + no-re-arm
pg_reset_audit; pg_reset_state; pg_state P4.t3 '["f.txt"]' 4
for d in d1 d2 d3 d4 d5; do pg_fail 4 P4.t3 "$d"; done
fire_pg coder >/dev/null
eq "5-fail → reason breaker-hard-5" "$(pg_field reason)" "breaker-hard-5"
eq "5-fail → would_stash true (FIX D, no hard-reset)" "$(pg_field would_stash)" "true"
eq "5-fail → tripped true" "$(pg_field tripped)" "true"

# no-re-arm: tripped state persists even after audit cleared
pg_reset_audit; pg_state P4.t3 '["f.txt"]' 4    # keep breaker.json (tripped=true)
fire_pg coder >/dev/null
eq "tripped → no-re-arm block on clean audit" "$(pg_field reason)" "tripped-no-rearm"

# E3 idempotency: 2 FAIL same diff → trip@2 (before 5)
pg_reset_audit; pg_reset_state; pg_state P4.t4 '["f.txt"]' 4
pg_fail 4 P4.t4 SAME; pg_fail 4 P4.t4 SAME
fire_pg coder >/dev/null
eq "same-diff 2-fail → reason idempotency-trip@2" "$(pg_field reason)" "idempotency-trip@2"
eq "same-diff → tripped true" "$(pg_field tripped)" "true"

# financial: files ∩ RISK_PATHS (case-folded: Wallet.php ∩ wallet) → STOP (P8: hard exit 2)
pg_reset_audit; pg_reset_state; pg_state P4.t5 '["application/controllers/Wallet.php"]' 4
out=$(fire_pg coder 2>&1); frc=$?
eq  "financial (CapCase) → reason financial-STOP" "$(pg_field reason)" "financial-STOP"
{ [ "$frc" -eq 2 ] && printf '%s' "$out" | grep -q HARD-BLOCK; } && ok "financial → HARD-BLOCK exit 2 (P8 active)" || no "financial exit2" "rc=$frc"

# E9 canary: logic self-check + heartbeat liveness
pg_reset_audit; pg_reset_state; pg_state P4.t6 '["f.txt"]' 4; fire_pg coder >/dev/null
cout=$(bash "$HPG" --canary "$PG")
has "canary logic OK (real FSM trips on synthetic 5-fail)" "$cout" "logic=OK"
has "canary liveness OK (fresh heartbeat)" "$cout" "liveness=OK"
has "canary liveness STALE (heartbeat aged out)" "$(ADP_NOW=99999999999 bash "$HPG" --canary "$PG")" "liveness=STALE"

# ---------------------------------------------------------------------------
echo "[12] P5 register hooks + PreCompact + FIX J + E5 hook-contract"
HSG="$HOOKS/stop-gate.sh"; HCC="$HOOKS/checkpoint-on-compact.sh"
HC="$ROOT_WS/docs/adr/hook-contract.md"; SETT="$CLAUDE_DIR/settings.json"
PROBE="$ROOT_WS/docs/reviews/pf3-hook-probe-2026-06-18.jsonl"

# E5: frozen hook-contract
[ -f "$HC" ] && ok "E5 hook-contract.md exists" || no "hook-contract" "thiếu"
{ grep -q 'subagent_type' "$HC" && grep -q 'agent_type' "$HC"; } && ok "E5 hook-contract has verified jq fields" || no "hc fields" "thiếu"
grep -q '2.1.158' "$HC" && ok "E5 hook-contract pins CC 2.1.158" || no "hc pin" "thiếu"

# E5 simulate-from-captured-log: feed the REAL probe payloads to the hooks
PT_RAW=$(python3 - "$PROBE" <<'PY' 2>/dev/null || true
import json, sys
for l in open(sys.argv[1]):
    o = json.loads(l)
    if o.get("event") == "PreToolUse": print(json.dumps(o["raw"]))
PY
)
SS_RAW=$(python3 - "$PROBE" <<'PY' 2>/dev/null || true
import json, sys
for l in open(sys.argv[1]):
    o = json.loads(l)
    if o.get("event") == "SubagentStop": print(json.dumps(o["raw"]))
PY
)
has "E5 sim: progress-guard parses real PreToolUse[Agent]" "$(printf '%s' "$PT_RAW" | bash "$HPG")" '"continue": true'
has "E5 sim: gate-verdict parses real SubagentStop" "$(printf '%s' "$SS_RAW" | bash "$HGV")" '"continue": true'

# FIX J: exec-loop flag turns off stop-gate phase-mode
has "FIX J: stop-gate ADP_EXEC_LOOP=1 → continue (no double-gate)" "$(printf '{}' | ADP_EXEC_LOOP=1 bash "$HSG")" '"continue": true'

# PreCompact insurance: synthetic root with an active IN_PROGRESS phase
CCR="$TMP/ccroot"; mkdir -p "$CCR/docs/tasks"
printf '<!-- ADP:MANIFEST -->\nSPEC_DIR: docs/tasks\n<!-- /ADP -->\n' > "$CCR/CLAUDE.md"
printf '<!-- ADP:PHASE 1 -->\nSTATUS: IN_PROGRESS\nGOAL: do x\nGATE: true\n<!-- /ADP -->\n' > "$CCR/docs/tasks/01-x.md"
ccout=$(printf '{"cwd":"%s","trigger":"manual"}' "$CCR" | bash "$HCC")
has "PreCompact: continue" "$ccout" '"continue": true'
[ -f "$CCR/SessionNext.md" ] && ok "PreCompact wrote SessionNext.md" || no "SessionNext" "không thấy"
grep -q 'IN_PROGRESS' "$CCR/SessionNext.md" 2>/dev/null && ok "SessionNext captures active phase" || no "SessionNext content" "thiếu"

# settings.json merge: valid + 3 new registrations + no clobber of old hooks
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SETT" 2>/dev/null && ok "settings.json valid JSON" || no "settings json" "hỏng"
python3 - "$SETT" <<'PY' 2>/dev/null && ok "settings.json registers 3 ADP hooks (gate-verdict/progress-guard/compact)" || no "settings reg" "thiếu"
import json, sys
d = json.load(open(sys.argv[1]))["hooks"]
ok = ("gate-verdict.sh" in json.dumps(d.get("SubagentStop", []))
      and "checkpoint-on-compact.sh" in json.dumps(d.get("PreCompact", []))
      and any(m.get("matcher") == "Agent" for m in d.get("PreToolUse", [])))
sys.exit(0 if ok else 1)
PY
python3 - "$SETT" <<'PY' 2>/dev/null && ok "settings.json no-clobber (old PreToolUse intact)" || no "no-clobber" "mất hook cũ"
import json, sys
pre = [m.get("matcher") for m in json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]]
sys.exit(0 if (pre.count("Bash") >= 2 and "Write|Edit" in pre) else 1)
PY

# ---------------------------------------------------------------------------
echo "[13] P6 RED-proof (TDD ordering) + E7 DoR pre-spawn gate"
P6="$TMP/p6"; mkdir -p "$P6/docs"
( cd "$P6" && git init -q && git config user.email t@t.t && git config user.name t \
   && echo base > w.txt && echo base > Wallet.php && git add -A && git commit -qm init ) 2>/dev/null
cat > "$P6/docs/.adp-project-profile.json" <<'JSON'
{"schema":"adp-project-profile/v1","project":"p6","risk_paths":["wallet","commission"],"skill_map":{"default":"x"}}
JSON
p6_state(){ # $1=task_id $2=acceptance_cmd $3=files_json
  printf '{"schema":"adp-handoff/v1","task_id":"%s","current_agent":"coder","files":%s,"acceptance_cmd":"%s","risk_tier":"low","parent_phase":"6","blast":"t"}' \
    "$1" "$3" "$2" > "$TMP/p6h.json"
  adp_exec_state_write "$P6" "$TMP/p6h.json" >/dev/null 2>&1
}
p6_fire(){ printf '{"cwd":"%s","agent_type":"coder"}' "$P6" | bash "$HGV"; }
p6_gv(){ adp_artifact_field "$P6/docs/.adp-gate-verdict.json" "$1"; }
mk_hand(){ # $1=task_id $2=acc $3=files_json [$4=risk]
  printf '{"schema":"adp-handoff/v1","task_id":"%s","current_agent":"coder","files":%s,"acceptance_cmd":"%s","risk_tier":"%s","parent_phase":"6","blast":"t"}' \
    "$1" "$3" "$2" "${4:-low}" > "$TMP/dor-$1.json"; echo "$TMP/dor-$1.json"; }

# --- RED-proof recording (adp-review.sh red) ---
rout=$(bash "$REVIEW" red "$P6" T.green 'true' w.txt 2>&1); rrc=$?
[ "$rrc" -ne 0 ] && ok "red: REFUSE test green-before-code (rc!=0)" || no "red refuse" "rc=$rrc"
has "red: refuse message" "$rout" "REFUSE"
( cd "$P6" && git checkout -- . ) 2>/dev/null
bash "$REVIEW" red "$P6" T.ok 'grep -q PATCHED w.txt' w.txt >/dev/null 2>&1
eq "red: records red_exit (grep fail=1)" "$(adp_red_proof_get "$P6" T.ok red_exit)" "1"
[ -n "$(adp_red_proof_get "$P6" T.ok acc_sha)" ] && ok "red: acc_sha hash-bound" || no "acc_sha" "thiếu"

# --- gate-verdict RED-proof enforcement ---
( cd "$P6" && git checkout -- . ) 2>/dev/null
bash "$REVIEW" red "$P6" T.full 'grep -q PATCHED w.txt' w.txt >/dev/null 2>&1   # RED
( cd "$P6" && echo PATCHED >> w.txt )                                            # implement
p6_state T.full 'grep -q PATCHED w.txt' '["w.txt"]'; p6_fire >/dev/null
eq "gate: valid RED→GREEN → PASS" "$(p6_gv verdict)" "PASS"

( cd "$P6" && git checkout -- . && echo PATCHED >> w.txt ) 2>/dev/null           # green, NO red recorded
p6_state T.nored 'grep -q PATCHED w.txt' '["w.txt"]'; p6_fire >/dev/null
eq "gate: green w/o red-proof → FAIL" "$(p6_gv verdict)" "FAIL"
has "gate: flag no-red-proof" "$(p6_gv flags)" "no-red-proof"

( cd "$P6" && git checkout -- . ) 2>/dev/null
bash "$REVIEW" red "$P6" T.swap 'grep -q PATCHED w.txt' w.txt >/dev/null 2>&1    # RED with cmd A
( cd "$P6" && echo PATCHED >> w.txt )
p6_state T.swap 'grep -q base w.txt' '["w.txt"]'; p6_fire >/dev/null             # GREEN with cmd B (passes)
eq "gate: RED/GREEN cmd swap → FAIL" "$(p6_gv verdict)" "FAIL"
has "gate: flag red-cmd-mismatch" "$(p6_gv flags)" "red-cmd-mismatch"

# --- E7 DoR pre-spawn gate ---
( cd "$P6" && git checkout -- . ) 2>/dev/null
bash "$REVIEW" red "$P6" D.ok 'grep -q PATCHED w.txt' w.txt >/dev/null 2>&1
hok=$(mk_hand D.ok 'grep -q PATCHED w.txt' '["w.txt"]')
dout=$(bash "$REVIEW" dor "$P6" "$hok"); drc=$?
[ "$drc" -eq 0 ] && ok "DoR: all-ready → PASS (rc0)" || no "dor pass" "rc=$drc: $dout"
has "DoR: PASS message" "$dout" "DoR PASS"

hnr=$(mk_hand D.nored 'grep -q PATCHED w.txt' '["w.txt"]')
dout=$(bash "$REVIEW" dor "$P6" "$hnr" 2>&1); drc=$?
[ "$drc" -ne 0 ] && ok "DoR: missing red-proof → FAIL" || no "dor nored" "rc=$drc"
has "DoR: flag no-red-proof" "$dout" "no-red-proof"

( cd "$P6" && git checkout -- . ) 2>/dev/null
bash "$REVIEW" red "$P6" D.risk 'grep -q PATCHED Wallet.php' Wallet.php >/dev/null 2>&1
hrk=$(mk_hand D.risk 'grep -q PATCHED Wallet.php' '["Wallet.php"]')
dout=$(bash "$REVIEW" dor "$P6" "$hrk" 2>&1); drc=$?
[ "$drc" -ne 0 ] && ok "DoR: risk-overlap no-ack → FAIL" || no "dor risk" "rc=$drc"
has "DoR: case-folded risk match (Wallet.php~wallet)" "$dout" "risk-overlap:wallet"
dout=$(bash "$REVIEW" dor "$P6" "$hrk" ack); drc=$?
[ "$drc" -eq 0 ] && ok "DoR: risk-overlap + Wyatt-ack → PASS" || no "dor ack" "rc=$drc: $dout"

hsy=$(mk_hand D.syn 'grep -q PATCHED |' '["w.txt"]')
dout=$(bash "$REVIEW" dor "$P6" "$hsy" 2>&1); drc=$?
[ "$drc" -ne 0 ] && ok "DoR: bad acc syntax → FAIL" || no "dor syntax" "rc=$drc"
has "DoR: flag acc-syntax" "$dout" "acc-syntax"

# ---------------------------------------------------------------------------
echo "[14] P7 shadow-calibration report (adp-shadow-report.sh)"
SR="$CLAUDE_DIR/tools/adp-shadow-report.sh"

CLEAN="$TMP/cal-clean.jsonl"; : > "$CLEAN"
for i in 1 2 3 4 5; do
  printf '{"gate":"gate-verdict","task":"c%s","outcome":"PASS"}\n' "$i" >> "$CLEAN"
  printf '{"gate":"review","task":"c%s","outcome":"APPROVE"}\n' "$i" >> "$CLEAN"
done
cout=$(bash "$SR" "$CLEAN")
has "report: clean N>=5 marker" "$cout" "[N>=5]"
has "report: clean → VERDICT GO" "$cout" "VERDICT: GO"
has "report: clean false-APPROVE 0" "$cout" "false-APPROVE: 0"

FA="$TMP/cal-fa.jsonl"; : > "$FA"
for i in 1 2 3 4; do
  printf '{"gate":"gate-verdict","task":"a%s","outcome":"PASS"}\n' "$i" >> "$FA"
  printf '{"gate":"review","task":"a%s","outcome":"APPROVE"}\n' "$i" >> "$FA"
done
printf '{"gate":"gate-verdict","task":"a5","outcome":"FAIL"}\n{"gate":"review","task":"a5","outcome":"APPROVE"}\n' >> "$FA"
fout=$(bash "$SR" "$FA")
has "report: false-APPROVE detected (=1)" "$fout" "false-APPROVE: 1"
has "report: false-APPROVE → VERDICT NO-GO" "$fout" "VERDICT: NO-GO"

FR="$TMP/cal-fr.jsonl"; : > "$FR"
for i in 1 2 3 4; do
  printf '{"gate":"gate-verdict","task":"r%s","outcome":"PASS"}\n' "$i" >> "$FR"
  printf '{"gate":"review","task":"r%s","outcome":"APPROVE"}\n' "$i" >> "$FR"
done
printf '{"gate":"gate-verdict","task":"r5","outcome":"PASS"}\n{"gate":"review","task":"r5","outcome":"REJECT"}\n' >> "$FR"
rfout=$(bash "$SR" "$FR")
has "report: false-REJECT detected (=1)" "$rfout" "false-REJECT: 1"
has "report: false-REJECT alone still GO" "$rfout" "VERDICT: GO"

SMALL="$TMP/cal-small.jsonl"; : > "$SMALL"
printf '{"gate":"gate-verdict","task":"s1","outcome":"PASS"}\n{"gate":"review","task":"s1","outcome":"APPROVE"}\n' >> "$SMALL"
sout=$(bash "$SR" "$SMALL")
has "report: N<5 marker" "$sout" "[N<5]"
has "report: N<5 → NO-GO" "$sout" "VERDICT: NO-GO"

mout=$(bash "$SR" "$TMP/does-not-exist.jsonl")
has "report: missing audit → NO-GO graceful" "$mout" "VERDICT: NO-GO"

# ---------------------------------------------------------------------------
echo "[15] P8 promote SHADOW→HARD-BLOCK + escape hatch + inert-safety + phase-bridge"
P8="$TMP/p8"; mkdir -p "$P8/docs"
( cd "$P8" && git init -q && git config user.email t@t.t && git config user.name t \
   && echo x > f.txt && git add -A && git commit -qm init ) 2>/dev/null
cat > "$P8/docs/.adp-project-profile.json" <<'JSON'
{"schema":"adp-project-profile/v1","project":"p8","risk_paths":["wallet"],"skill_map":{"default":"x"}}
JSON
p8_state(){ # $1=task_id $2=files_json
  printf '{"schema":"adp-handoff/v1","task_id":"%s","current_agent":"coder","files":%s,"acceptance_cmd":"true","risk_tier":"low","parent_phase":"8","blast":"t"}' \
    "$1" "$2" > "$TMP/p8h.json"
  adp_exec_state_write "$P8" "$TMP/p8h.json" >/dev/null 2>&1
}
p8_fire(){ printf '{"cwd":"%s","tool_input":{"subagent_type":"coder"}}' "$P8" | bash "$HPG"; }
p8_reset(){ : > "$P8/docs/.adp-audit.jsonl"; rm -f "$P8/docs/.adp-breaker.json"; }

# financial-STOP → HARD-BLOCK exit 2 (the dangerous money-path is REFUSED)
p8_reset; p8_state P8.fin '["Wallet.php"]'
out=$(p8_fire 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q HARD-BLOCK; } && ok "P8: financial-STOP → HARD-BLOCK exit 2" || no "p8 fin exit2" "rc=$rc"

# escape hatch: ADP_FORCE_SHADOW=1 → continue (override), exit 0
out=$(printf '{"cwd":"%s","tool_input":{"subagent_type":"coder"}}' "$P8" | ADP_FORCE_SHADOW=1 bash "$HPG"); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"continue": true'; } && ok "P8: ADP_FORCE_SHADOW escape → exit 0 + continue" || no "p8 escape" "rc=$rc"

# clean allow → exit 0 + continue (real work never blocked)
p8_reset; p8_state P8.ok '["f.txt"]'
out=$(p8_fire); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"continue": true'; } && ok "P8: clean allow → exit 0 + continue" || no "p8 allow" "rc=$rc"

# INERT without exec-state: non-ADP session is NEVER blocked (key safety property)
rm -f "$P8/docs/.adp-exec-state.json"
out=$(p8_fire); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"continue": true'; } && ok "P8: no exec-state → exit 0 (hard-block inert for non-ADP)" || no "p8 inert" "rc=$rc"

# breaker-hard-5 → HARD-BLOCK exit 2
p8_reset; p8_state P8.brk '["f.txt"]'
for d in d1 d2 d3 d4 d5; do printf '{"gate":"gate-verdict","phase":"8","task":"P8.brk","outcome":"FAIL","task_diff":"%s"}\n' "$d" >> "$P8/docs/.adp-audit.jsonl"; done
out=$(p8_fire 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "P8: breaker-hard-5 → HARD-BLOCK exit 2" || no "p8 brk exit2" "rc=$rc"

# gate-verdict P8: active mode + phase-bridge nudge on PASS (end-to-end RED→GREEN)
GVP="$TMP/gvp8"; mkdir -p "$GVP"
( cd "$GVP" && git init -q && git config user.email t@t.t && git config user.name t \
   && echo base > a.txt && git add -A && git commit -qm init ) 2>/dev/null
bash "$REVIEW" red "$GVP" gp.1 'grep -q PATCHED a.txt' a.txt >/dev/null 2>&1
( cd "$GVP" && echo PATCHED >> a.txt )
printf '{"schema":"adp-handoff/v1","task_id":"gp.1","current_agent":"coder","files":["a.txt"],"acceptance_cmd":"grep -q PATCHED a.txt","risk_tier":"low","parent_phase":"8","blast":"t"}' > "$TMP/gvp8h.json"
adp_exec_state_write "$GVP" "$TMP/gvp8h.json" >/dev/null 2>&1
gvout=$(printf '{"cwd":"%s","agent_type":"coder"}' "$GVP" | bash "$HGV")
has "P8: gate-verdict PASS → phase-bridge nudge" "$gvout" "phase-bridge"
eq  "P8: gate-verdict cache mode=active" "$(adp_artifact_field "$GVP/docs/.adp-gate-verdict.json" mode)" "active"

# ---------------------------------------------------------------------------
echo "[16] task_f1f2063f — case-fold unify adp_allowed_risk_overlap (ALL floor call-sites)"
# Folding lives in the canonical fn → fixes checkpoint floor-rule, session-start warn, AND
# progress-guard financial-STOP in ONE place. These cases hit the exact call those sites make.
ov=$(adp_allowed_risk_overlap "application/controllers/Wallet.php" "wallet,commission") \
  && ok "overlap: CapCase Wallet.php ∩ wallet → MATCH (was the under-flag gap)" || no "capcase" "rc=$?"
eq  "overlap: echoes ORIGINAL case (messages read naturally)" "$ov" "application/controllers/Wallet.php"
adp_allowed_risk_overlap "app/wallet_lib.php" "wallet" >/dev/null \
  && ok "overlap: lowercase still matches (regression)" || no "lc" "rc=$?"
adp_allowed_risk_overlap "x/Commission.php" "WALLET,COMMISSION" >/dev/null \
  && ok "overlap: UPPER risk_paths folded too (both sides)" || no "upper" "rc=$?"
adp_allowed_risk_overlap "docs/readme.md,src/util.php" "wallet,commission" >/dev/null \
  && no "non-overlap should rc1" "got rc0" || ok "overlap: genuine non-overlap → rc1 (no false-positive)"
ov=$(adp_allowed_risk_overlap "src/Util.php,app/Commission.php" "wallet,commission") \
  && eq "overlap: multi-file picks the money one (Commission.php)" "$ov" "app/Commission.php" || no "multi" "rc=$?"
# unification cleanup: progress-guard no longer pre-folds (relies on the source fix)
hasnt "unify: progress-guard dropped local pre-fold (FILES_LC)" "$(cat "$HOOKS/progress-guard.sh")" "FILES_LC"
# live call-sites call the fn RAW (so the source fix actually reaches them)
has "unify: checkpoint floor-rule calls fn raw" "$(cat "$TOOLS/adp-checkpoint.sh")" 'adp_allowed_risk_overlap "$ALLOWED" "$RISK_PATHS_M"'

# ---------------------------------------------------------------------------
echo "[18] adp-profile-gen.sh — bootstrap profile from committed manifest"
GEN="$TOOLS/adp-profile-gen.sh"
PG2="$TMP/pgen"; mkdir -p "$PG2"
cat > "$PG2/CLAUDE.md" <<'MD'
## ADP Manifest
<!-- ADP:MANIFEST -->
GATE_RUNNER: .venv/bin/python -m pytest -q -x
RISK_PATHS: agent/orchestrator.py, bridge/, auth/
SPEC_DIR: docs/tasks
EXECUTOR_SKILL: drnick-coder
CHECKPOINT_PREFIX: adp
<!-- /ADP -->
MD
bash "$GEN" "$PG2" >/dev/null 2>&1
[ -f "$PG2/docs/.adp-project-profile.json" ] && ok "profile-gen: created profile from manifest" || no "gen create" "không thấy"
eq "profile-gen: schema" "$(adp_profile_get "$PG2" schema)" "adp-project-profile/v1"
eq "profile-gen: gate_runner from manifest" "$(adp_profile_get "$PG2" gate_runner)" ".venv/bin/python -m pytest -q -x"
eq "profile-gen: skill_map.default = executor_skill" "$(adp_profile_skill "$PG2" anything)" "drnick-coder"
adp_risk_overlap_ci "$PG2" "agent/Orchestrator.py" >/dev/null && ok "profile-gen: risk_paths feed the financial gate (case-folded)" || no "gen risk" "rc=$?"
has "profile-gen: create-if-missing (no clobber)" "$(bash "$GEN" "$PG2")" "exists"
has "profile-gen: --force regenerates" "$(bash "$GEN" "$PG2" --force)" "generated"

# ---------------------------------------------------------------------------
echo "[19] adp-dashboard.sh — HTML admin dashboard generator"
DASH="$TOOLS/adp-dashboard.sh"
DROOT="$TMP/dash"; mkdir -p "$DROOT/docs"
cat > "$DROOT/docs/.adp-audit.jsonl" <<'JSONL'
{"ts":"2026-06-18T10:00:00+0700","gate":"gate-verdict","outcome":"PASS","task":"d.1","phase":"1"}
{"ts":"2026-06-18T10:01:00+0700","gate":"gate-verdict","outcome":"FAIL","task":"d.2","phase":"1","flags":"no-red-proof"}
{"ts":"2026-06-18T10:02:00+0700","gate":"progress-guard","decision":"block","reason":"financial-STOP","task":"d.3"}
{"ts":"2026-06-18T10:03:00+0700","gate":"review","outcome":"REFUSED","reason":"diff-mismatch","phase":"1"}
JSONL
DHTML="$TMP/dash.html"
ADP_DASH_ROOT="$DROOT" bash "$DASH" "$DHTML" >/dev/null 2>&1
[ -f "$DHTML" ] && ok "dashboard: HTML generated" || no "dash gen" "không thấy"
hasnt "dashboard: placeholder replaced (no __DATA__)" "$(cat "$DHTML")" "__DATA__"
python3 - "$DHTML" <<'PYEOF' && ok "dashboard: embedded JSON valid + classifies 3 issues" || no "dash json" "parse/issues sai"
import re, json, sys
h = open(sys.argv[1]).read()
d = json.loads(re.search(r'const DATA = (\{.*\});', h, re.S).group(1))
assert len(d["events"]) == 4, "events"
assert sorted(i["kind"] for i in d["issues"]) == ["breaker BLOCK", "checkpoint REFUSED", "gate FAIL"], d["issues"]
sys.exit(0)
PYEOF
has "dashboard: surfaces financial-STOP detail" "$(cat "$DHTML")" "financial-STOP"

# ---------------------------------------------------------------------------
echo "[16] Task#20 P1 — dynamic-path portability (no baked workspace path)"
WSP="/Users/wyattngo/Sites/localhost"
HT_HITS=$(grep -rlE "$WSP" "$HOOKS"/*.sh "$TOOLS"/*.sh 2>/dev/null | grep -v '\.bak' | wc -l | tr -d ' ')
[ "$HT_HITS" = "0" ] && ok "P1: 0 baked workspace path in hooks/tools" || no "P1 hooks/tools path" "$HT_HITS file con literal"
DYN_OK=1
for f in gate-verdict progress-guard stop-gate checkpoint-on-compact pre-edit-guard session-start-context; do
  grep -q 'BASH_SOURCE' "$HOOKS/$f.sh" 2>/dev/null || DYN_OK=0
done
for t in adp-checkpoint adp-profile-gen adp-review adp-status; do
  grep -q 'BASH_SOURCE' "$TOOLS/$t.sh" 2>/dev/null || DYN_OK=0
done
[ "$DYN_OK" = "1" ] && ok "P1: ADP hooks+tools resolve lib via BASH_SOURCE" || no "P1 dyn resolve" "thieu BASH_SOURCE"
REL="$TMP/relocate"; mkdir -p "$REL"
cp "$HOOKS/adp-lib.sh" "$HOOKS/gate-verdict.sh" "$REL/" 2>/dev/null
if echo '{}' | bash "$REL/gate-verdict.sh" >/dev/null 2>&1; then ok "P1: relocated gate-verdict runs (sources lib by BASH_SOURCE)"; else no "P1 relocate" "moved hook crashed"; fi
AGD="$HOME/.claude/agents"
AG_HITS=$(grep -rlE "Sites/localhost" "$AGD/coder.md" "$AGD/bug-fixer.md" "$AGD/senior-engineer.md" "$AGD/tech-lead.md" 2>/dev/null | wc -l | tr -d ' ')
[ "$AG_HITS" = "0" ] && ok "P1: 0 baked path in 4 role agents" || no "P1 agents path" "$AG_HITS agent con literal"

# ---------------------------------------------------------------------------
echo "[17] Task#20 P2 — adp-bootstrap.sh auto-setup"
BS="$TOOLS/adp-bootstrap.sh"
[ -x "$BS" ] && ok "P2: adp-bootstrap.sh exists+executable" || no "P2 bootstrap missing" "not executable"
# 17.1 profile-gen now emits adp_home (closes P1 runtime-token gap)
PJ="$TMP/p2prof"; mkdir -p "$PJ"
printf '# p\n<!-- ADP:MANIFEST -->\nGATE_RUNNER: pytest -q\nRISK_PATHS: payments, auth\nSPEC_DIR: docs/tasks\nEXECUTOR_SKILL:\nCHECKPOINT_PREFIX: adp\n<!-- /ADP -->\n' > "$PJ/CLAUDE.md"
bash "$TOOLS/adp-profile-gen.sh" "$PJ" >/dev/null 2>&1
python3 -c "import json,sys; d=json.load(open('$PJ/docs/.adp-project-profile.json')); sys.exit(0 if d.get('adp_home') else 1)" 2>/dev/null \
  && ok "P2: profile-gen emits adp_home" || no "P2 adp_home" "missing field"
# 17.2 bootstrap a python project → detect + MANIFEST + profile + settings-merge (isolated settings)
PYP="$TMP/p2py"; mkdir -p "$PYP"; echo "pytest" > "$PYP/requirements.txt"
SETT="$TMP/p2-settings.json"; echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"OLD"}]}]}}' > "$SETT"
ADP_SETTINGS_FILE="$SETT" bash "$BS" "$PYP" >/dev/null 2>&1
has "P2: bootstrap writes ADP:MANIFEST into project" "$(cat "$PYP/CLAUDE.md" 2>/dev/null)" "ADP:MANIFEST"
has "P2: detected python gate_runner=pytest" "$(cat "$PYP/CLAUDE.md" 2>/dev/null)" "pytest"
[ -f "$PYP/docs/.adp-project-profile.json" ] && ok "P2: bootstrap generated profile" || no "P2 profile" "not generated"
python3 -c "import json,sys; d=json.load(open('$SETT')); h=json.dumps(d); sys.exit(0 if all(x in h for x in ['progress-guard.sh','gate-verdict.sh','checkpoint-on-compact.sh']) and 'OLD' in h else 1)" 2>/dev/null \
  && ok "P2: settings merged 3 ADP hooks (no-clobber, OLD intact)" || no "P2 settings merge" "clobber or missing"
# 17.3 idempotent re-run — settings byte-identical
B1=$(md5 -q "$SETT" 2>/dev/null || md5sum "$SETT" | cut -d' ' -f1)
ADP_SETTINGS_FILE="$SETT" bash "$BS" "$PYP" >/dev/null 2>&1
B2=$(md5 -q "$SETT" 2>/dev/null || md5sum "$SETT" | cut -d' ' -f1)
[ "$B1" = "$B2" ] && ok "P2: bootstrap idempotent (settings unchanged on re-run)" || no "P2 idempotent" "settings changed"
# 17.4 unknown stack → emit adp-decision/v1 + STOP (no silent guess)
UNK="$TMP/p2unk"; mkdir -p "$UNK"; echo "hello" > "$UNK/readme.txt"
ADP_SETTINGS_FILE="$TMP/p2-unk-settings.json" bash "$BS" "$UNK" >/dev/null 2>&1; RC=$?
DECF="$UNK/docs/.adp-decision-pending.json"
if [ -f "$DECF" ] && python3 -c "import json,sys; d=json.load(open('$DECF')); sys.exit(0 if d.get('schema')=='adp-decision/v1' and len(d.get('options',[]))==3 else 1)" 2>/dev/null; then
  ok "P2: unknown stack → adp-decision/v1 (3 options) emitted"
else no "P2 decision" "no conformant decision artifact"; fi
[ "$RC" = "3" ] && ok "P2: unknown stack STOPs (exit 3, no silent setup)" || no "P2 stop-code" "rc=$RC (want 3)"

# ---------------------------------------------------------------------------
echo "[18] Task#20 P3 — 3-option Decision Protocol (DOP)"
DEC="$TOOLS/adp-decide.sh"; DGATE="$HOOKS/decision-gate.sh"
[ -x "$DEC" ] && ok "P3: adp-decide.sh exists+executable" || no "P3 decide missing" "not exec"
[ -x "$DGATE" ] && ok "P3: decision-gate.sh exists+executable" || no "P3 gate missing" "not exec"
# fixture builder: $1=outfile $2=n_options $3=n_recommended
mkdecision(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
out=sys.argv[1]; n=int(sys.argv[2]); rec=int(sys.argv[3])
ids=["A","B","C","D"]
opts=[{"id":ids[i],"title":f"opt{i}","approach":"do x","pros":["p"],"cons":["c"],
       "risk":"low","effort":"S","recommended": i<rec} for i in range(n)]
json.dump({"schema":"adp-decision/v1","id":"D-t","trigger":"coding","context":"ctx",
          "options":opts,"chosen":None,"decided_by":None,"ts":None}, open(out,"w"), indent=2)
PY
}
VALID="$TMP/d-valid.json"; mkdecision "$VALID" 3 1
bash "$DEC" validate "$VALID" >/dev/null 2>&1 && ok "P3: validator ACCEPTS 3-option/1-recommended" || no "P3 accept" "rejected valid"
B2OPT="$TMP/d-2.json"; mkdecision "$B2OPT" 2 1
bash "$DEC" validate "$B2OPT" >/dev/null 2>&1 && no "P3 reject-2" "accepted 2-option" || ok "P3: validator REJECTS 2 options"
B4OPT="$TMP/d-4.json"; mkdecision "$B4OPT" 4 1
bash "$DEC" validate "$B4OPT" >/dev/null 2>&1 && no "P3 reject-4" "accepted 4-option" || ok "P3: validator REJECTS 4 options"
B0REC="$TMP/d-0r.json"; mkdecision "$B0REC" 3 0
bash "$DEC" validate "$B0REC" >/dev/null 2>&1 && no "P3 reject-0rec" "accepted 0-recommended" || ok "P3: validator REJECTS 0 recommended"
B2REC="$TMP/d-2r.json"; mkdecision "$B2REC" 3 2
bash "$DEC" validate "$B2REC" >/dev/null 2>&1 && no "P3 reject-2rec" "accepted 2-recommended" || ok "P3: validator REJECTS 2 recommended"
# resolve → sets chosen + appends jsonl + clears open
RREPO="$TMP/p3repo"; mkdir -p "$RREPO/docs"; cp "$VALID" "$RREPO/docs/.adp-decision-pending.json"
bash "$DEC" resolve "$RREPO/docs/.adp-decision-pending.json" B wyatt >/dev/null 2>&1
CH=$(python3 -c "import json;print(json.load(open('$RREPO/docs/.adp-decision-pending.json')).get('chosen'))" 2>/dev/null)
[ "$CH" = "B" ] && ok "P3: resolve sets chosen=B" || no "P3 resolve" "chosen=$CH"
[ -f "$RREPO/docs/.adp-decisions.jsonl" ] && grep -q '"chosen": *"B"\|"chosen":"B"' "$RREPO/docs/.adp-decisions.jsonl" && ok "P3: resolve appends .adp-decisions.jsonl" || no "P3 jsonl" "no log line"
# decision-gate: open decision → SHADOW logs would-block, ALWAYS continue:true
GREPO="$TMP/p3gate"; mkdir -p "$GREPO/docs"; mkdecision "$GREPO/docs/.adp-decision-pending.json" 3 1
GOUT=$(printf '{"cwd":"%s"}' "$GREPO" | bash "$DGATE" 2>/dev/null)
echo "$GOUT" | grep -q '"continue": *true' && ok "P3: decision-gate open→SHADOW continue:true" || no "P3 gate shadow" "blocked in shadow: $GOUT"
# no open decision → continue; failure-safe on garbage
printf '{"cwd":"%s"}' "$TMP/nope" | bash "$DGATE" 2>/dev/null | grep -q '"continue": *true' && ok "P3: decision-gate no-decision→continue" || no "P3 gate none" "did not continue"
printf 'garbage' | bash "$DGATE" 2>/dev/null | grep -q '"continue": *true' && ok "P3: decision-gate failure-safe (garbage→continue)" || no "P3 gate failsafe" "crashed"
# settings.json registers decision-gate on Stop
python3 -c "import json,sys;s=json.load(open('$CLAUDE_DIR/settings.json'));sys.exit(0 if 'decision-gate.sh' in json.dumps(s.get('hooks',{}).get('Stop',[])) else 1)" 2>/dev/null \
  && ok "P3: settings registers decision-gate on Stop" || no "P3 settings reg" "not registered"

# ---------------------------------------------------------------------------
echo "[19] Task#20 P4 — generic-coder gated mode (kills D3)"
# fixtures: a no-skill stack (allow_generic on/off) + a skill-present stack (regression)
P4GEN="$TMP/p4gen"; mkdir -p "$P4GEN/docs"
cat > "$P4GEN/docs/.adp-project-profile.json" <<'JSON'
{"schema":"adp-project-profile/v1","skill_map":{"default":""},"allow_generic":true,"risk_paths":["wallet","payment"]}
JSON
P4OFF="$TMP/p4off"; mkdir -p "$P4OFF/docs"
cat > "$P4OFF/docs/.adp-project-profile.json" <<'JSON'
{"schema":"adp-project-profile/v1","skill_map":{"default":""},"allow_generic":false,"risk_paths":["wallet"]}
JSON
P4SKL="$TMP/p4skill"; mkdir -p "$P4SKL/docs"
cat > "$P4SKL/docs/.adp-project-profile.json" <<'JSON'
{"schema":"adp-project-profile/v1","skill_map":{"backend":"ci3-code-generator","default":""},"allow_generic":false,"risk_paths":["wallet"]}
JSON
# 19.1 allow_generic reader: explicit true/false
eq "P4: allow_generic reader → true"  "$(adp_profile_allow_generic "$P4GEN")" "true"
eq "P4: allow_generic reader → false" "$(adp_profile_allow_generic "$P4OFF")" "false"
# 19.2 skill present → canonical skill path UNCHANGED (regression: allow_generic irrelevant)
out=$(adp_coder_mode "$P4SKL" backend "app/foo.php"); rc=$?
{ [ "$out" = "skill:ci3-code-generator" ] && [ "$rc" -eq 0 ]; } && ok "P4: skill present → skill:<name> rc0 (path unchanged)" || no "P4 skill path" "out=$out rc=$rc"
# 19.3 no-skill + allow_generic + non-risk file → generic (gated) rc0
out=$(adp_coder_mode "$P4GEN" backend "app/util.py"); rc=$?
{ [ "$out" = "generic" ] && [ "$rc" -eq 0 ]; } && ok "P4: no-skill+allow_generic+safe → generic rc0" || no "P4 generic ok" "out=$out rc=$rc"
# 19.4 no-skill + allow_generic + RISK_PATHS file + NO ack → REFUSE rc1 (STOP+Decision)
out=$(adp_coder_mode "$P4GEN" backend "src/Wallet.php"); rc=$?
{ case "$out" in REFUSE:risk-overlap:wallet*) [ "$rc" -ne 0 ];; *) false;; esac; } && ok "P4: generic+risk no-ack → REFUSE rc1" || no "P4 risk refuse" "out=$out rc=$rc"
# 19.5 no-skill + allow_generic + RISK_PATHS file + Wyatt ack → generic rc0
out=$(adp_coder_mode "$P4GEN" backend "src/Wallet.php" ack); rc=$?
{ [ "$out" = "generic" ] && [ "$rc" -eq 0 ]; } && ok "P4: generic+risk+ack → generic rc0" || no "P4 risk ack" "out=$out rc=$rc"
# 19.6 no-skill + allow_generic DISABLED (default-deny) → REFUSE rc1, never silent generic
out=$(adp_coder_mode "$P4OFF" backend "app/util.py"); rc=$?
{ case "$out" in REFUSE:*) [ "$rc" -ne 0 ];; *) false;; esac; } && ok "P4: no-skill+generic-disabled → REFUSE rc1 (default-deny)" || no "P4 deny" "out=$out rc=$rc"
# 19.7 coder.md documents the generic gate (CHECK 7: new mechanism must be guarded in agent doc)
has "P4: coder.md documents generic gate (adp_coder_mode)" "$(cat "$HOME/.claude/agents/coder.md" 2>/dev/null)" "adp_coder_mode"


# ---------------------------------------------------------------------------
echo "[21] P1b diff-binding — file untracked (lỗ đo 2026-07-23)"
# `git diff HEAD` KHÔNG thấy file untracked ⇒ phase nào thêm file MỚI thì verdict
# REVIEW/SMOKE bị bind vào một diff không chứa dòng code nào của deliverable.
UR="$TMP/repo-untracked"; mkdir -p "$UR"
( cd "$UR" && git init -q && git config user.email t@t.t && git config user.name t \
   && echo base > tracked.txt && printf 'ignored.txt\n' > .gitignore \
   && git add tracked.txt .gitignore && git commit -qm init ) 2>/dev/null

( cd "$UR" && echo edit >> tracked.txt )
U_BASE=$(adp_work_diff_sha "$UR")
( cd "$UR" && printf 'def a():\n    return 1\n' > brandnew.py )
U_NEW=$(adp_work_diff_sha "$UR")
[ "$U_BASE" != "$U_NEW" ] && ok "thêm file untracked → hash ĐỔI (lỗ cũ: không đổi)" \
  || no "untracked vào hash" "hash đứng yên khi thêm file mới ($U_BASE)"
has "git diff HEAD thấy file mới sau add -N" "$(cd "$UR" && git --no-pager diff HEAD --name-only)" "brandnew.py"

# file gitignore (.env/venv) KHÔNG được lọt vào hash — --exclude-standard
( cd "$UR" && echo 'SECRET=1' > ignored.txt )
eq "file gitignore KHÔNG vào hash" "$(adp_work_diff_sha "$UR")" "$U_NEW"

# ADP_HASH_EXCLUDE — artifact/state của CHÍNH gate không được vào hash, nếu không
# gate tự phá nó: adp-review.sh tính SHA rồi MỚI ghi docs/reviews/*.json ⇒ không trừ
# thì mọi review REFUSE 100%; audit log thì bị GHI trong lúc chấm ⇒ chấm làm đổi diff.
adp_audit_event "$UR" gate=selftest outcome=X
eq "audit log (docs/.adp-*) KHÔNG vào hash" "$(adp_work_diff_sha "$UR")" "$U_NEW"
mkdir -p "$UR/docs/reviews" "$UR/docs/smokes"
echo '{}' > "$UR/docs/reviews/self.json"; echo 'x' > "$UR/docs/smokes/self.md"
eq "review/smoke artifact KHÔNG vào hash (chống tự phá)" "$(adp_work_diff_sha "$UR")" "$U_NEW"

# tất định: review-time và checkpoint-time phải ra CÙNG hash, nếu không = REFUSE giả
eq "hash tất định qua 2 lần gọi" "$(adp_work_diff_sha "$UR")" "$(adp_work_diff_sha "$UR")"
eq "add -N chỉ chạm index, không đổi nội dung file" "$(cat "$UR/brandnew.py")" "$(printf 'def a():\n    return 1\n')"

# CASE chính: stamp xong → viết lại FILE MỚI → checkpoint phải REFUSE
printf '{"verdict":"APPROVE","model":"haiku"}' > "$TMP/vin-u.json"
bash "$TOOLS/adp-review.sh" stamp "$UR" "$TMP/vin-u.json" "$TMP/art-u.json" >/dev/null 2>&1
( ROOT="$UR" REVIEW_VAL="PASS ref=$TMP/art-u.json" REVIEW_REF="$TMP/art-u.json"; review_validate_artifact medium >/dev/null 2>&1 ) \
  && ok "stamp xong, chưa sửa gì → allowed" || no "bound match (untracked)" "rc=$?"
( cd "$UR" && printf 'def a():\n    return 999  # viết lại SAU review\n' > brandnew.py )
( ROOT="$UR" REVIEW_VAL="PASS ref=$TMP/art-u.json" REVIEW_REF="$TMP/art-u.json"; review_validate_artifact medium >/dev/null 2>&1 ) \
  && no "sửa file MỚI sau stamp phải refuse" "got rc0 — verdict cũ vẫn được nhận" \
  || ok "sửa file MỚI sau stamp → REFUSED"

# per-task binding (gate-verdict): task chỉ đẻ file mới từng bị chấm no-op-diff FAIL
TS_SHA=$(adp_task_diff_sha "$UR" brandnew.py)
[ -n "$TS_SHA" ] && ok "adp_task_diff_sha: task chỉ có file mới → có hash (was no-op-diff)" \
  || no "task_diff_sha untracked" "rỗng"
# scope guard từng fail-OPEN: file MỚI ngoài scope không hiện trong --name-only
# (docs/ khai luôn: review_validate_artifact ở trên đã ghi docs/.adp-audit.jsonl vào
#  repo này, nếu không khai thì nó mới là file out-of-scope đầu tiên và case đo nhầm)
( cd "$UR" && printf 'x\n' > sneaky.py )
OOS_U=$(adp_task_diff_in_scope "$UR" "brandnew.py,tracked.txt,docs"); SCOPE_U=$?
[ "$SCOPE_U" -ne 0 ] && ok "scope guard bắt file MỚI ngoài scope" \
  || no "scope guard untracked" "fail-open: rc0 dù sneaky.py ngoài scope"
eq "scope guard chỉ đúng file mới vi phạm" "$OOS_U" "sneaky.py"
