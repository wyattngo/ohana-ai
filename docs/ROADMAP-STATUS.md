# ROADMAP STATUS — ohana-ai (L3, SINH MÁY)

> **AUTO-GENERATED bởi `.claude/tools/adp-roadmap.sh` @ 2026-07-24T17:10.**
> Đây là VIEW join từ L1 (`docs/ROADMAP.md`) × L2 (`docs/tasks/*.md`) × git — **KHÔNG phải source of truth**.
> ĐỪNG sửa tay phía trên `NOTES_HUMAN`. Muốn đổi kế hoạch → sửa L1. Muốn đổi trạng thái → chạy `adp-checkpoint.sh`.

## Mục tiêu 100%

**Internal: 13/36 work item hoàn tất (36%)** ← đây là mẫu số của "100% Roadmap"
External: 0/9 (0%) — chờ bên thứ ba, **không tính vào 100%**
Phase gate-passed: 39/52



## GĐ0 → GĐ3 — internal (đếm vào 100%)

| Roadmap ID | Trạng thái | Phase done | Phase trỏ tới |
|---|---|---|---|
| `GD0-BOOTSTRAP` | ✅ DONE | 5/5 | 01:1 02:1.0 02:1.1 02:1.2 02:1.3  |
| `GD0-CHAT` | ✅ DONE | 3/3 | 07:G0 07:G1 07:G2  |
| `GD0-COALESCE` | ⚪ chưa có spec | 0/0 | — |
| `GD0-CONFIG` | ✅ DONE | 3/3 | 05:P0 05:P1 05:P2  |
| `GD0-DRAFTER` | 🔶 một phần | 3/6 | 13:D0 13:D1 15:P1 15:P2 15:P3 15:P4  |
| `GD0-DRAFTSCHEMA` | ✅ DONE | 1/1 | 14:A0  |
| `GD0-EMBED` | ✅ DONE | 3/3 | 08:E0 08:E1 08:E2  |
| `GD0-EVAL` | ⬜ TODO | 0/1 | 03:6  |
| `GD0-FOUNDATION` | ✅ DONE | 3/3 | 06:F0 06:F2 09:C0  |
| `GD0-HISTORY` | ✅ DONE | 3/3 | 10:H0 10:H1 10:H2  |
| `GD0-INGEST` | ✅ DONE | 2/2 | 14:B0 14:C0  |
| `GD0-INTENT` | ⬜ TODO | 0/1 | 03:8  |
| `GD0-METER` | ⬜ TODO | 0/1 | 03:5  |
| `GD0-MULTITENANT` | ✅ DONE | 1/1 | 01:2  |
| `GD0-OBS` | 🔶 một phần | 1/2 | 03:9 12:W0  |
| `GD0-PII` | ⚪ chưa có spec | 0/0 | — |
| `GD0-POLICY` | ✅ DONE | 1/1 | 01:5  |
| `GD0-RESIDENCY` | ⚪ chưa có spec | 0/0 | — |
| `GD0-ROUTER` | ⬜ TODO | 0/1 | 03:7  |
| `GD0-SHOPS` | ✅ DONE | 4/4 | 11:S0 11:S1 11:S2 11:S3  |
| `GD0-SPLIT` | ⚪ chưa có spec | 0/0 | — |
| `GD0-TOOLS` | ⛔ BLOCKED | 1/2 | 01:4 03:4  |
| `GD0-UI` | ✅ DONE | 3/3 | 04:P0 04:P1 04:P2  |
| `GD0-WIKI` | ⛔ BLOCKED | 1/2 | 01:3 03:3  |
| `GD0-WINDOW` | ⛔ BLOCKED | 0/1 | 03:10  |
| `GD0-ZALO` | ⛔ BLOCKED | 0/1 | 03:2  |
| `GD1-STATE` | ⚪ chưa có spec | 0/0 | — |
| `GD2-ANALYTICS` | ⚪ chưa có spec | 0/0 | — |
| `GD2-CARRIER` | ⚪ chưa có spec | 0/0 | — |
| `GD2-CHANNEL` | ✅ DONE | 1/1 | 06:F1  |
| `GD2-DISCOVERY` | ⚪ chưa có spec | 0/0 | — |
| `GD2-RECONCILE` | ⚪ chưa có spec | 0/0 | — |
| `GD3-BILLING` | ⚪ chưa có spec | 0/0 | — |
| `GD3-HARDEN` | ⚪ chưa có spec | 0/0 | — |
| `GD3-RESELLER` | ⚪ chưa có spec | 0/0 | — |
| `GD3-SOAK` | ⚪ chưa có spec | 0/0 | — |

## External — chờ bên thứ ba (đếm riêng)

| Roadmap ID | Trạng thái | Phase done | Phase trỏ tới |
|---|---|---|---|
| `GD0-TOOLS` | ⛔ BLOCKED | 1/2 | 01:4 03:4  |
| `GD0-WINDOW` | ⛔ BLOCKED | 0/1 | 03:10  |
| `GD0-ZALO` | ⛔ BLOCKED | 0/1 | 03:2  |
| `GD1-COD` | ⚪ chưa có spec | 0/0 | — |
| `GD1-PAY` | ⚪ chưa có spec | 0/0 | — |
| `GD1-SHIP` | ⚪ chưa có spec | 0/0 | — |
| `GD2-MESSENGER` | ⚪ chưa có spec | 0/0 | — |
| `GD3-AUDIT` | ⚪ chưa có spec | 0/0 | — |
| `GD3-RECURRING` | ⚪ chưa có spec | 0/0 | — |

## ⚠️ Uncovered — mục L1 chưa spec nào nhận

- `GD0-COALESCE` (internal)
- `GD0-PII` (internal)
- `GD0-RESIDENCY` (internal)
- `GD0-SPLIT` (internal)
- `GD1-COD` (external)
- `GD1-PAY` (external)
- `GD1-SHIP` (external)
- `GD1-STATE` (internal)
- `GD2-ANALYTICS` (internal)
- `GD2-CARRIER` (internal)
- `GD2-DISCOVERY` (internal)
- `GD2-MESSENGER` (external)
- `GD2-RECONCILE` (internal)
- `GD3-AUDIT` (external)
- `GD3-BILLING` (internal)
- `GD3-HARDEN` (internal)
- `GD3-RECURRING` (external)
- `GD3-RESELLER` (internal)
- `GD3-SOAK` (internal)

## ⚠️ Unplanned — phase không trỏ về roadmap nào

Phase ở đây là **scope drift**: đang làm việc không nằm trong kế hoạch, hoặc thiếu khoá nối `ROADMAP:`.

- `(none)` ← 03-Task-GD0-AcceptanceBackfill.md phase 1



## Lịch sử mẫu số internal

- 2026-07-19T12:38 25 internal_denominator
- 2026-07-20T13:23 27 internal_denominator
- 2026-07-20T21:23 28 internal_denominator
- 2026-07-21T17:10 33 internal_denominator
- 2026-07-23T15:27 36 internal_denominator

<!-- NOTES_HUMAN — phần dưới đây generator KHÔNG ghi đè -->
