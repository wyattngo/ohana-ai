# CLAUDE.md — Ohana AI Seller (project router)

> **Sub-project của workspace `localhost/`.** Router level 0 tại `../CLAUDE.md`.
> Owner: Tân (dev lead) · Approver: Wyatt Ngo (fractional CTO)
> Last updated: 2026-07-16 · Status: **PRE-BOOTSTRAP** (chưa init code, đang audit spec)

---

## 1. Định danh

| Field | Value |
|---|---|
| Project | Ohana AI Seller (GĐ0 MVP) |
| Kind | AI copilot cho seller social-commerce VN (Zalo/FB/IG) |
| Stack (dự kiến) | Python 3.x / FastAPI / PostgreSQL + pgvector / Redis / Alembic — **fork chọn lọc từ `drnickv4/`** |
| Repo | `ohana-ai` (chưa init) |
| Duration | 3–4 tuần, Zalo-only |
| Priority order | safety → user trust → stability → growth (KHÔNG dùng fintech Survival Framework) |
| Parent workspace | `/Users/wyattngo/Sites/localhost/` |

---

## 2. Trạng thái hiện tại

- ⚠️ **Chưa có code.** Repo chưa init. Đang ở giai đoạn audit spec.
- Spec canonical: `docs/tasks/01-Task-OhanaAISeller-GD0.md` (chờ Wyatt duyệt tier RISK cho từng phase).
- Chưa clear PRE-001..005 (xem spec §6).
- Chưa fork/port module nào từ `drnickv4/`.

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

## 8. Pre-flight blocking (chờ Wyatt/Tân)

| ID | Chờ ai | Nội dung |
|---|---|---|
| PRE-001 | Claude/dev | Đọc `drnickv4/db/models.py` body để biết có scaffold tenant sẵn không |
| PRE-002 | Tân/nền tảng | Ohana platform REST API spec (order/shipping/product/account endpoints) |
| PRE-003 | Tân | Wiki docs source (Notion/Drive/markdown) + format |
| PRE-004 | Tân | Zalo OA credentials + webhook contract + rate-limit thật (48h/8-msg window) |
| PRE-005 | Wyatt | Confirm channel đầu = Zalo OA (không phải FB/Meta) |
| PRE-006 | Wyatt | Cardinality tenant: `shop_id` đủ, hay cần cả `seller_id`/`tenant_id` (1 seller nhiều shop?) |

Chưa clear PRE-* → KHÔNG bootstrap Phase 1.

---

*Router level 1. Workspace router ở `../CLAUDE.md`. Convention thư mục ở `../FOLDER-CONVENTION.md`.*
