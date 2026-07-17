# CLAUDE.md — Ohana AI Seller (project router)

> **Sub-project của workspace `localhost/`.** Router level 0 tại `../CLAUDE.md`.
> Owner: Tân (dev lead) · Approver: Wyatt Ngo (fractional CTO)
> Last updated: 2026-07-17 · Status: **SPEC 01 = 100% DONE (Phase 1–5 shipped)** — F1 wiki-RAG + F2 API Q&A (mock endpoints) + F3 policy-gate/pending_reply/inbox scaffold all landed; PRE-002/003/004 backfill deferred until source landed.

---

## 1. Định danh

| Field | Value |
|---|---|
| Project | Ohana AI Seller (GĐ0 MVP) |
| Kind | AI copilot cho seller social-commerce VN (Zalo/FB/IG) |
| Stack | Python 3.11 / FastAPI / PostgreSQL + pgvector / Alembic — **fork chọn lọc từ `drnickv4/`**. Redis chưa wire (Phase 3+). |
| Repo | `ohana-ai` (init) — branch `main`, phases 1–5 shipped, no remote configured |
| Duration | 3–4 tuần, Zalo-only |
| Priority order | safety → user trust → stability → growth (KHÔNG dùng fintech Survival Framework) |
| Parent workspace | `/Users/wyattngo/Sites/localhost/` |

---

## 2. Trạng thái hiện tại

- ✅ **Spec 01 = 100% (5/5 phases DONE)** · Overall ADP 9/9 phase gate-passed (100%).
- Spec canonical: `docs/tasks/01-Task-OhanaAISeller-GD0.md` — tất cả phase blocks ở STATUS: DONE với EVIDENCE stamped.
- Latest STATE_HASH: `1b5cf0eabdfd` @ phase-5 close (2026-07-17).
- **Shipped surface:**
  - Phase 2 (RISK:high) — `auth/identity.py` HS256, `db/{models,session,repos}.py` tenant-first + Alembic 0001, `retrieval/pgvector.py PgvectorRetriever(shop_scope=)` SQL-level hard filter, gate `tests/test_tenant_isolation.py` 3/3.
  - Phase 3 (low) — `parsing/{chunk,ingest}.py`, `tools/{registry,wiki}.py`, `api/admin.py` ingest, gate `test_wiki_rag.py` 2/2 (happy + adversarial ns iso).
  - Phase 4 (medium) — `bridge/ohana_client.py` R1.1-extended REST client (verify=True hardcoded), `tools/ohana_read.py order_status`, gate `test_ohana_tools.py` 10/10 (MockTransport).
  - Phase 5 (RISK:high) — `agent/{policy_gate,orchestrator}.py`, `db/models.py PendingReply` + Alembic 0002, `bridge/zalo_sender.py MockZaloSender`, `api/{webhook,inbox}.py` scaffolds, gate `test_policy_gate + test_orchestrator + test_tenant_isolation` 12/12.
- **Blocking backfill (không chặn gate — chặn real-endpoint content):**
  - PRE-002 — real Ohana platform API endpoint spec chưa từ Tân → order_status test hiện là MockTransport contract; F2 tools thứ 2/3/4 (shipping/product/account) chưa land.
  - PRE-003 — real Wiki docs corpus chưa land → ingest hoạt động, chỉ chưa có nội dung thật.
  - PRE-004 — Zalo OA creds + webhook signature + rate-limit spec chưa từ Tân → webhook `enabled=False` default, `MockZaloSender` thay real sender, send-on-approve worker chưa wire.
- Cleared: PRE-001 (drnickv4/db/models.py đọc + tenant-first design landed Phase 2), PRE-005 (Zalo-first confirmed by Wyatt lock in 2026-07-16 spec approval), PRE-006 (`shop_id` alone confirmed sufficient qua tất cả Phase 2 tests).

---

## 3. Nguồn port (đọc trước khi build)

**KHÔNG fork nguyên `drnickv4/` repo.** Port chọn lọc từng module, viết mới phần multi-tenant.

| Từ `drnickv4/` | Sang `ohana-ai/` | Ghi chú |
|---|---|---|
| `agent/llm_client.py` + `providers/` | `agent/llm_client.py` + `providers/` | Reuse nguyên |
| `agent/embedder.py`, `retrieval/`, `parsing/`, `storage/` | Cùng path | Reuse — thêm `shop_id` scope SQL-level |
| `agent/orchestrator.py` | `agent/orchestrator.py` | Adapt async cho F3 pending_reply |
| `tools/registry.py` | `tools/registry.py` | Port nguyên shape Tool dataclass |
| `bridge/onfa_client.py` | `bridge/ohana_client.py` | Viết mới theo pattern REST + verify=True |
| `auth/identity.py` + `auth/jwt.py` | Cùng path | Mở rộng JWT claim `(user_id, shop_id, role)` |
| `db/models.py` | Viết lại tenant-first | **KHÔNG copy** — DrNick single-tenant |
| `.claude/hooks/guardrail.py` | Cùng path | Đổi R1.13 money → intent-safety Ohana |
| Reviewer subagent, CI workflow, Alembic skeleton, RULES/ADP | Reuse | ADP discipline giữ nguyên |

**KHÔNG port sang:** `bridge/onfa_client.py`, `tools/onfa_actions.py`, `pending_action` financial logic, ConfirmEvent 2FA path.

---

## 4. Trigger signals (routing)

Chuyển sang project này khi user nhắc:
`Ohana`, `Ohana AI`, `ohana-ai`, `Zalo OA`, `seller copilot`, `Wiki RAG`, `policy_gate`, `pending_reply`, `shop_id`, `multi-tenant`, `platform_wiki`, `GĐ0 MVP`, `Tân`.

**Skill auto-trigger:** `drnick-coder` (reuse — Plan-Patch-Verify Python/FastAPI phù hợp Ohana), `onfa-spec-generator` (nếu cần thêm spec phase), `onfa-brief-formatter` (intake brief mới).

---

## 5. ADP Manifest (v2.3 — Wyatt finalize RISK per phase)

<!-- ADP:MANIFEST -->
GATE_RUNNER: .venv/bin/python -m pytest -q -x
RISK_PATHS: agent/orchestrator.py, agent/policy_gate.py, tools/registry.py, bridge/, auth/, db/migrations, api/webhook.py, api/chat.py
SPEC_DIR: docs/tasks
EXECUTOR_SKILL: drnick-coder
CHECKPOINT_PREFIX: adp
<!-- /ADP -->

**Isolation**: Ohana AI dùng ADP v2.3 riêng (`ohana-ai/.claude/`), KHÔNG dùng workspace v1.3 của Onfa/DrNick. Sandbox: an toàn để calibrate decision-gate (SHADOW → hard-block sau ≥5 real decisions).

Xem `docs/adr/hook-contract.md` + `MODEL.md` bundle export cho contract chi tiết. Workspace router `../CLAUDE.md §4.7` mô tả v1.3 flow (áp dụng Onfa/DrNick).

---

## 6. Layout dự kiến (sau khi bootstrap)

```
ohana-ai/
├── CLAUDE.md              ← File này (router project)
├── pyproject.toml
├── Dockerfile
├── app/                   FastAPI entrypoint
├── agent/                 orchestrator, llm_client, embedder, policy_gate (NET-NEW)
├── providers/             LLM providers
├── retrieval/             pgvector wrapper (shop_id-scoped)
├── parsing/               Wiki doc chunker
├── storage/               Storage abstractions
├── bridge/
│   └── ohana_client.py    REST client platform API
├── auth/                  identity + jwt (multi-tenant)
├── tools/
│   ├── registry.py
│   ├── wiki.py            F1 search_wiki
│   └── ohana_read.py      F2 order/shipping/product/account
├── api/
│   ├── admin.py           Wiki ingest
│   ├── webhook.py         Zalo inbound
│   └── chat.py            Seller chat/inbox
├── db/
│   ├── models.py          Tenant-first (shop_id everywhere)
│   └── migrations/        Alembic
├── web/                   Seller inbox UI (framework TBD)
├── tests/
├── .claude/               (port từ drnickv4/ khi bootstrap)
└── docs/
    ├── tasks/             Spec ADP (01-Task-OhanaAISeller-GD0.md đã có)
    ├── briefs/            Project-specific briefs
    └── memory/            SESSION_LOG, DECISIONS, KNOWN_ISSUES
```

---

## 7. Anti-patterns (giữ từ DrNick + Ohana-specific)

🚫 Auto-send tới khách KHÔNG qua `policy_gate.py` — kể cả demo/dev.
🚫 Intent nhạy cảm (complaint / refund / price_negotiation / specific_order) auto-send.
🚫 Vector query hoặc DB query KHÔNG include `shop_id` scope SQL-level (post-filter = R1.22 violation).
🚫 Đọc `user_id` / `shop_id` / `role` từ request body hoặc webhook payload thay vì verified JWT.
🚫 Fork nguyên `drnickv4/` repo — luôn port chọn lọc.
🚫 Copy `db/models.py` từ DrNick — single-tenant, phải viết lại tenant-first.
🚫 Skip TDD gate (test ĐỎ trước khi impl) cho phase RISK: high (Phase 2, Phase 5).
🚫 Self-certify DONE mà không qua `adp-checkpoint.sh` (spine quyết, không phải LLM).

---

## 8. Pre-flight status (updated 2026-07-17)

| ID | Status | Chờ ai | Nội dung / resolution |
|---|---|---|---|
| PRE-001 | ✅ RESOLVED | — | `drnickv4/db/models.py` đọc trong phase 2 discovery; single-tenant confirmed → viết lại tenant-first (`shop_id NOT NULL` mọi bảng). |
| PRE-002 | ⏳ BLOCKING (backfill) | Tân/nền tảng | Ohana platform REST API spec. Phase 4 gate GREEN qua MockTransport contract; `bridge/ohana_client.py` shape locked; F2 tools thứ 2/3/4 (shipping_info/product_info/account_lookup) chờ endpoint list. |
| PRE-003 | ⏳ BLOCKING (backfill) | Tân | Real wiki docs corpus location + format. Phase 3 gate GREEN qua inline fixture; `parsing/{chunk,ingest}.py` + `api/admin.py` ingest endpoint ready to accept real content. |
| PRE-004 | ⏳ BLOCKING (backfill) | Tân | Zalo OA creds + webhook signature + rate-limit. Phase 5 gate GREEN qua `MockZaloSender`; `bridge/zalo_sender.py` interface locked; webhook `enabled=False` default until sig-verify + shops table land. |
| PRE-005 | ✅ RESOLVED | — | Zalo-first confirmed via spec 01 approval 2026-07-16. |
| PRE-006 | ✅ RESOLVED | — | `shop_id` alone sufficient — all Phase 2 tenant-isolation tests pass with single-scalar scope; no `seller_id`/`tenant_id` needed at GĐ0 (revisit if per-seller-many-shops case emerges in Phase 6+). |

Contract gates all GREEN với mock/fixture. Real-content backfill = separate follow-up specs khi source landed, KHÔNG chặn milestone gate.

---

*Router level 1. Workspace router ở `../CLAUDE.md`. Convention thư mục ở `../FOLDER-CONVENTION.md`.*
