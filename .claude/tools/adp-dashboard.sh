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
# Primary = the repo this dashboard lives in. In the isolated ohana-ai checkout ROOT
# IS the repo root (not a workspace parent), so label it by basename. Workspace siblings
# are aggregated ONLY when they actually exist on disk — DEC-OHANA-03 "một nguồn": don't
# advertise phantom repos in an isolated checkout.
roots = [(os.path.basename(root.rstrip("/")) or ".", root)]
for _sib in ("Localhost Onfa", "drnickv4"):
    _p = os.path.join(root, _sib)
    if os.path.isdir(_p):
        roots.append((_sib, _p))
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

# --- roadmap L3 (docs/ROADMAP-STATUS.md) — sync the dashboard with the 3-tier spine ---
# DEC-OHANA-03: L1×L2×git → L3 (adp-roadmap.sh). The dashboard is a read-only presentation
# layer over L3; if L3 is absent it degrades to a "generate it" note (never crashes).
import re as _re

def parse_roadmap(base):
    f = os.path.join(base, "docs", "ROADMAP-STATUS.md")
    rm = {"present": False}
    if not os.path.isfile(f):
        return rm
    txt = open(f, errors="replace").read()
    rm["present"] = True
    m = _re.search(r"AUTO-GENERATED .*? @ ([0-9T:\-]+)", txt)
    rm["generated"] = m.group(1) if m else ""
    rm["denom_warn"] = bool(_re.search(r"MẪU SỐ GIẢM", txt))

    def trio(pat):
        mm = _re.search(pat, txt)
        return {"done": int(mm.group(1)), "total": int(mm.group(2)),
                "pct": int(mm.group(3))} if mm else None
    rm["internal"] = trio(r"Internal:\s*(\d+)/(\d+)\s*work item.*?\((\d+)%\)")
    rm["external"] = trio(r"External:\s*(\d+)/(\d+)\s*\((\d+)%\)")
    mm = _re.search(r"Phase gate-passed:\s*(\d+)/(\d+)", txt)
    rm["phase"] = {"done": int(mm.group(1)), "total": int(mm.group(2))} if mm else None

    def rows(section_re):
        blk = _re.search(section_re, txt, _re.S)
        out = []
        if blk:
            for line in blk.group(1).splitlines():
                r = _re.match(r"\|\s*`([^`]+)`\s*\|\s*([^|]+?)\s*\|\s*(\d+/\d+)\s*\|\s*([^|]*?)\s*\|", line)
                if r:
                    out.append({"id": r.group(1), "state": r.group(2).strip(),
                                "prog": r.group(3), "phases": r.group(4).strip()})
        return out
    rm["internal_rows"] = rows(r"## GĐ0 → GĐ3 — internal.*?\n(.*?)\n## ")
    rm["external_rows"] = rows(r"## External —.*?\n(.*?)\n## ")

    def bullets(section_re, prefix="- "):
        blk = _re.search(section_re, txt, _re.S)
        if not blk:
            return []
        return [ln[len(prefix):].strip() for ln in blk.group(1).splitlines()
                if ln.startswith(prefix)]
    rm["uncovered"] = bullets(r"## ⚠️ Uncovered.*?\n(.*?)\n## ")
    rm["unplanned"] = [b for b in bullets(r"## ⚠️ Unplanned.*?\n(.*?)\n(?:## |<!--|\Z)")
                       if b.startswith("`")]
    return rm

roadmap = parse_roadmap(root)

payload = {
    "meta": {"generated": ts, "spine": spine, "force_shadow": fs,
             "sources": sources, "stats": stats},
    "roadmap": roadmap,
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
  <div class="sub">generated <span id="gen"></span> · ADP spine + roadmap L1×L2×L3 (DEC-OHANA-03) · re-run <code>bash .claude/tools/adp-dashboard.sh</code> to refresh</div>
  <div class="banner" id="banner"></div>

  <h2>Roadmap coverage — L1×L2×L3 spine</h2>
  <div class="banner" id="rm-banner"></div>
  <div class="legend" id="rm-note"></div>
  <div id="rm-tables"></div>

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

// --- roadmap coverage (L3) — synced with the 3-tier spine (DEC-OHANA-03) ---
// NB: payload always carries a roadmap object. Do NOT end any statement/comment below
// with a brace-then-semicolon: the spine-test DATA extractor greedily captures the DATA
// literal up to the LAST brace-semicolon in the file, so a stray one steals its match.
const RM = DATA.roadmap;
const rmb=document.getElementById("rm-banner"),
      rmn=document.getElementById("rm-note"),
      rmt=document.getElementById("rm-tables");
if(!RM || !RM.present){
  rmb.innerHTML="";
  rmn.innerHTML=`<span class="warn">No docs/ROADMAP-STATUS.md (L3) found</span> — run <code>bash .claude/tools/adp-roadmap.sh</code> to generate it.`;
} else {
  const frac=o=>o?`${o.done}/${o.total}`:"—", pct=o=>o?` (${o.pct}%)`:"";
  const nUnc=(RM.uncovered||[]).length, nUnp=(RM.unplanned||[]).length;
  rmb.innerHTML=[
    card("Internal (100% target)", frac(RM.internal)+pct(RM.internal),
         (RM.internal&&RM.internal.pct>=100)?"b-ok":"b-warn", "mẫu số của mục tiêu 100%"),
    card("External (3rd-party)", frac(RM.external)+pct(RM.external),
         "b-warn", "đếm riêng — không vào 100%"),
    card("Phase gate-passed", frac(RM.phase), "b-ok", "adp-status.sh: phase đã ký"),
    card("Drift", `${nUnc} unc · ${nUnp} unpl`,
         nUnp>0?"b-bad":(nUnc>0?"b-warn":"b-ok"), "uncovered · unplanned"),
  ].join("");
  const warn=RM.denom_warn?`<span class="bad">⚠ MẪU SỐ GIẢM — tín hiệu gian lận chỉ số (L1 §0.2)</span> · `:"";
  rmn.innerHTML=`${warn}L3 generated <code>${esc(RM.generated||"?")}</code> · re-run <code>adp-roadmap.sh</code> to refresh · `+
    `<span class="muted">✅ DONE · 🔶 một phần · ⬜ TODO · ⛔ BLOCKED · ⚪ chưa có spec</span>`;
  const rmTable=(title,rows)=> (!rows||!rows.length)?"":
    `<h2>${esc(title)}</h2><table><thead><tr><th>roadmap id</th><th>state</th><th>phase done</th><th>phase trỏ tới</th></tr></thead><tbody>`+
    rows.map(r=>`<tr><td class="info">${esc(r.id)}</td><td>${esc(r.state)}</td>`+
      `<td class="nowrap">${esc(r.prog)}</td><td class="muted">${esc(r.phases)}</td></tr>`).join("")+
    `</tbody></table>`;
  rmt.innerHTML=rmTable("Internal — đếm vào 100%", RM.internal_rows)+
                rmTable("External — chờ bên thứ ba", RM.external_rows);
}
</script>
</body></html>"""

# safe-embed: neutralize any literal </script> inside data so it can't break out of the tag
DATA_JS = json.dumps(payload, ensure_ascii=False).replace("</", "<\\/")
open(out, "w").write(TEMPLATE.replace("__DATA__", DATA_JS))
print("dashboard:", out, "| events:", len(events), "| issues:", len(issues), "| spine:", spine, "| force_shadow:", fs)
PY
