#!/bin/bash
# =============================================================================
# adp-dashboard.sh — generate a SELF-CONTAINED HTML admin dashboard for the ADP
# control-plane: spine status + ADP_FORCE_SHADOW, the audit logs, and the issues/bugs
# the spine caught (FAIL / breaker-block / REFUSED / DoR-fail / red-proof-refuse).
#
# Reads (whatever exists): <workspace>/docs/.adp-audit.jsonl + each project repo's
# docs/.adp-audit.jsonl. Data is baked into the HTML → opens OFFLINE, no server.
# Re-run to refresh.
#
# Usage: adp-dashboard.sh [out.html]      (default: <workspace>/docs/adp-dashboard.html)
#   ADP_FORCE_SHADOW is read from THIS shell's env (per-session; the page says so).
# =============================================================================
set -uo pipefail

# ROOT = workspace (data aggregation + default out). Override with ADP_DASH_ROOT for tests.
ROOT="${ADP_DASH_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
OUT="${1:-$ROOT/docs/adp-dashboard.html}"
# spine-state grep always reads the REAL hooks (next to this script), not the data root.
HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"

# spine promotion state (P8): hard_block present + gate-verdict mode active ⇒ ACTIVE
SPINE="SHADOW"
if grep -q 'hard_block()' "$HOOKS/progress-guard.sh" 2>/dev/null \
   && grep -q '"mode": "active"' "$HOOKS/gate-verdict.sh" 2>/dev/null; then
    SPINE="ACTIVE"
fi
FS="${ADP_FORCE_SHADOW:-0}"

python3 - "$OUT" "$ROOT" "$SPINE" "$FS" <<'PY'
import sys, json, os, datetime, html as _html

out, root, spine, fs = sys.argv[1:5]
ts = datetime.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")

# --- aggregate audit logs from workspace root + project repos -----------------
roots = [(".", root),
         ("Localhost Onfa", os.path.join(root, "Localhost Onfa")),
         ("drnickv4", os.path.join(root, "drnickv4"))]
events = []
sources = []
for label, base in roots:
    f = os.path.join(base, "docs", ".adp-audit.jsonl")
    n = 0
    if os.path.isfile(f):
        for line in open(f, errors="replace"):
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except Exception:
                continue
            e["_repo"] = label
            events.append(e)
            n += 1
    sources.append({"repo": label, "count": n})

events.sort(key=lambda e: e.get("ts", ""), reverse=True)

# --- classify "issues / bugs the spine caught" -------------------------------
def issue_of(e):
    g, o = e.get("gate", ""), (e.get("outcome", "") or "").upper()
    dec = (e.get("decision", "") or "").lower()
    if g == "gate-verdict" and o == "FAIL":
        return ("gate FAIL", e.get("flags", "") or "test failed")
    if g == "progress-guard" and dec == "block":
        return ("breaker BLOCK", e.get("reason", ""))
    if g == "review" and o == "REFUSED":
        return ("checkpoint REFUSED", e.get("reason", ""))
    if g == "dor" and o == "FAIL":
        return ("DoR FAIL", e.get("reasons", ""))
    if g == "red-proof" and o == "REFUSE":
        return ("red-proof REFUSE", e.get("reason", "test green before code"))
    return None

issues = []
for e in events:
    it = issue_of(e)
    if it:
        issues.append({"ts": e.get("ts", ""), "repo": e.get("_repo", ""),
                       "kind": it[0], "detail": it[1],
                       "task": e.get("task", ""), "phase": e.get("phase", "")})

stats = {
    "total": len(events),
    "issues": len(issues),
    "by_gate": {},
    "fails": sum(1 for e in events if (e.get("outcome", "") or "").upper() == "FAIL"),
    "blocks": sum(1 for e in events if (e.get("decision", "") or "").lower() == "block"),
}
for e in events:
    g = e.get("gate", "?")
    stats["by_gate"][g] = stats["by_gate"].get(g, 0) + 1

payload = {
    "meta": {"generated": ts, "spine": spine, "force_shadow": fs,
             "sources": sources, "stats": stats},
    "events": events[:300],   # cap for page weight
    "issues": issues,
}

TEMPLATE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ADP Control-Plane Dashboard</title>
<style>
  :root{--bg:#0b0e14;--panel:#121722;--ink:#e6e9ef;--mut:#8b93a7;--line:#222a39;
        --green:#37d67a;--red:#ff5d6c;--amber:#ffb454;--blue:#5aa9ff;--mono:ui-monospace,SFMono-Regular,Menlo,monospace}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif}
  .wrap{max-width:1100px;margin:0 auto;padding:28px 20px 60px}
  h1{font-size:20px;margin:0 0 2px;letter-spacing:.2px}
  .sub{color:var(--mut);font-size:12px;margin-bottom:22px}
  .banner{display:flex;gap:14px;flex-wrap:wrap;margin-bottom:22px}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:14px 16px;min-width:150px;flex:1}
  .card .k{color:var(--mut);font-size:11px;text-transform:uppercase;letter-spacing:.6px}
  .card .v{font-size:22px;font-weight:600;margin-top:4px;font-family:var(--mono)}
  .pill{display:inline-block;padding:2px 8px;border-radius:999px;font-size:11px;font-weight:600;font-family:var(--mono)}
  .ok{color:var(--green)} .bad{color:var(--red)} .warn{color:var(--amber)} .info{color:var(--blue)}
  .b-ok{background:rgba(55,214,122,.14);color:var(--green)}
  .b-bad{background:rgba(255,93,108,.16);color:var(--red)}
  .b-warn{background:rgba(255,180,84,.16);color:var(--amber)}
  h2{font-size:13px;text-transform:uppercase;letter-spacing:.8px;color:var(--mut);margin:26px 0 10px}
  table{width:100%;border-collapse:collapse;font-family:var(--mono);font-size:12.5px}
  th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}
  th{color:var(--mut);font-weight:500;font-size:11px;text-transform:uppercase;letter-spacing:.5px}
  tr:hover td{background:#0f1420}
  .muted{color:var(--mut)} .nowrap{white-space:nowrap}
  input{background:var(--panel);border:1px solid var(--line);color:var(--ink);border-radius:8px;padding:7px 11px;width:240px;font-family:var(--mono)}
  .empty{color:var(--mut);padding:14px 10px;font-style:italic}
  .legend{color:var(--mut);font-size:11px;margin-top:8px}
</style></head>
<body><div class="wrap">
  <h1>ADP Control-Plane Dashboard</h1>
  <div class="sub">generated <span id="gen"></span> · spec #19 spine · re-run <code>bash .claude/tools/adp-dashboard.sh</code> to refresh</div>
  <div class="banner" id="banner"></div>

  <h2>Issues / bugs caught by the spine</h2>
  <table id="issues"><thead><tr><th>time</th><th>repo</th><th>kind</th><th>detail</th><th>task</th><th>phase</th></tr></thead><tbody></tbody></table>

  <h2>Audit log — recent activity <input id="q" placeholder="filter (gate, repo, task, outcome)…"></h2>
  <table id="log"><thead><tr><th>time</th><th>repo</th><th>gate</th><th>outcome</th><th>task</th><th>phase</th><th>detail</th></tr></thead><tbody></tbody></table>
  <div class="legend">mode column reflects the event when written; <span class="ok">green</span>=PASS/APPROVE/allow · <span class="bad">red</span>=FAIL/REJECT/block/REFUSE · <span class="warn">amber</span>=other.</div>
</div>
<script>
const DATA = __DATA__;
const esc = s => (s==null?"":String(s)).replace(/[&<>]/g, c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));
function cls(o){o=(o||"").toUpperCase(); if(["PASS","APPROVE","ALLOW","PASS-LEGACY","RECORDED"].includes(o))return"ok";
  if(["FAIL","REJECT","BLOCK","REFUSE","REFUSED"].includes(o))return"bad"; return "warn";}
function shortTs(t){return (t||"").replace("T"," ").replace(/\+.*/,"");}

const m=DATA.meta, s=m.stats;
const spineBad = m.spine!=="ACTIVE" || m.force_shadow==="1";
document.getElementById("gen").textContent = m.generated;
document.getElementById("banner").innerHTML = [
  card("Spine", m.spine, m.spine==="ACTIVE"?"b-ok":"b-warn"),
  card("ADP_FORCE_SHADOW", m.force_shadow==="1"?"ON (override)":"off", m.force_shadow==="1"?"b-warn":"b-ok", "this shell only"),
  card("Audit events", s.total, "b-ok", m.sources.map(x=>x.repo+":"+x.count).join("  ")),
  card("Issues caught", s.issues, s.issues>0?"b-bad":"b-ok", "FAIL "+s.fails+" · block "+s.blocks),
].join("");
function card(k,v,b,note){return `<div class="card"><div class="k">${esc(k)}</div>
  <div class="v"><span class="pill ${b}">${esc(v)}</span></div>
  ${note?`<div class="muted" style="font-size:11px;margin-top:7px">${esc(note)}</div>`:""}</div>`;}

const ib=document.querySelector("#issues tbody");
ib.innerHTML = DATA.issues.length ? DATA.issues.map(i=>`<tr>
  <td class="nowrap muted">${esc(shortTs(i.ts))}</td><td>${esc(i.repo)}</td>
  <td class="bad">${esc(i.kind)}</td><td>${esc(i.detail)}</td>
  <td>${esc(i.task)}</td><td>${esc(i.phase)}</td></tr>`).join("")
  : `<tr><td colspan="6" class="empty">No issues caught — clean.</td></tr>`;

const lb=document.querySelector("#log tbody"), q=document.getElementById("q");
function detailOf(e){return e.flags||e.reason||e.reasons||e.ref||e.producer||"";}
function render(){
  const f=(q.value||"").toLowerCase();
  const rows=DATA.events.filter(e=>!f || JSON.stringify(e).toLowerCase().includes(f));
  lb.innerHTML = rows.length ? rows.map(e=>{
    const o=e.outcome||e.decision||"";
    return `<tr><td class="nowrap muted">${esc(shortTs(e.ts))}</td><td>${esc(e._repo)}</td>
      <td class="info">${esc(e.gate)}</td><td class="${cls(o)}">${esc(o||"·")}</td>
      <td>${esc(e.task||"")}</td><td>${esc(e.phase||"")}</td>
      <td class="muted">${esc(detailOf(e))}</td></tr>`;}).join("")
    : `<tr><td colspan="7" class="empty">no events match.</td></tr>`;
}
q.addEventListener("input",render); render();
</script>
</body></html>"""

# safe-embed: neutralize any literal </script> inside data so it can't break out of the tag
DATA_JS = json.dumps(payload, ensure_ascii=False).replace("</", "<\\/")
open(out, "w").write(TEMPLATE.replace("__DATA__", DATA_JS))
print("dashboard:", out, "| events:", len(events), "| issues:", len(issues), "| spine:", spine, "| force_shadow:", fs)
PY
