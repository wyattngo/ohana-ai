---
adr_id: 2026-07-22-derivation-pipeline
title: Derivation pipeline 4 tầng (workflow → gates → ROADMAP → L2)
status: ACCEPTED
approved_by: wyatt
approved_at: 2026-07-22
supersedes: null
relates_to: DEC-OHANA-05 (backend-workflow authoritative)
---

# ADR — Derivation pipeline: từ BDUF planning sang JIT derivation

> **Signed 2026-07-22 (Wyatt).** Hai lựa chọn mở đã chốt: **F3 = rule chính**
> (Section 3, aggregate STATUS — KHÔNG dùng alternative Class-split); **F4 =
> token phase**, gate **grep-only** (Section 4).

## Section 1 — Context & motivation

### 1.1 Root cause của reject v7

ROADMAP v7 §9.3 (planning heuristics) yêu cầu cluster 26 work item → 10 spec
TRƯỚC khi bắt tay code. Dù bản grounded đã map từ `docs/tasks/` thật, §9.3-C
("đề xuất cluster cho item chưa có spec") vẫn là **BDUF fabrication**: nó ép
tác giả đoán ranh giới spec của công việc CHƯA làm. Wyatt không đọc được tương
lai — cluster đúng chỉ lộ ra khi code chạm vào, không phải ở tầng planning.

Kết luận: planning heuristics như một RULE (cách derive) thì đúng; như một
BẢNG CLUSTER TIỀN CHẾ thì sai. Tách hai thứ đó là mục tiêu ADR này.

### 1.2 Vấn đề nền tảng chưa giải (đằng sau reject)

Hai lỗ hổng L3 coverage tồn tại độc lập với §9.3, không bản patch cluster nào
chạm tới — vì chúng là vấn đề SEMANTIC của cách đếm coverage:

- **F3 — Fragmented ID.** Một `GD?-X` xuất hiện ở nhiều spec với STATUS khác
  nhau (đo thật 2026-07-22): `GD0-TOOLS` DONE-part ở spec 01 + BLOCKED ở spec
  03; `GD0-OBS` DONE ở spec 12 + TODO ở spec 03; `GD0-DRAFTER` DONE ở spec 13 +
  TODO ở spec 15. L3 hiện KHÔNG định nghĩa coverage aggregate khi một ID trải
  nhiều spec ⇒ một ID có thể vừa "đã DONE" vừa "còn TODO", đếm nhập nhằng.

- **F4 — ADR-only ID.** `GD0-RESIDENCY` acceptance = "ADR ACCEPTED + data-flow"
  (`docs/adr/2026-07-18-hosting-region.md`, ACCEPTED). Không phase block nào
  mang `ROADMAP: GD0-RESIDENCY` ⇒ L3 đếm nó **uncovered vĩnh viễn** dù việc đã
  xong. Coverage rule hiện giả định "mọi ID phải có ≥1 phase" — sai với ID mà
  bằng chứng hoàn thành là một quyết định kiến trúc, không phải code.

### 1.3 F1/F2/F5 disposition

- **F1** (tách túi 03) + **F2** (slug collision) → **N/A**: hệ quả của §9.3
  preemptive, bỏ cùng paradigm cũ. Túi 03 = tech debt refactor JIT khi bắt tay,
  không proactive.
- **F5** (brief ref §8) → fix cơ học ngoài ADR (patch `CLAUDE-CODE-BRIEF.md` line 47: `ROADMAP §8` → `backend-workflow.md §8`).
## Section 2 — Decision

Adopt **derivation pipeline 4 tầng**:

    backend-workflow.md   (WHY + shape — Wyatt viết, nguồn neo)
        ↓ derives (enforced pre-commit + CI)
    docs/gates/           (target + test policy — CC propose, Wyatt sign)
        ↓ contracts
    ROADMAP.md §4         (work item + field `derives_from`)
        ↓ triage MATCH/FITS/OUT (brief §2)
    docs/tasks/           (L2 spec — CC sinh JIT khi code)
        ↓ implements
    Code + test → Gate closed → Step → Phase → GĐ

Nguyên tắc:
1. **Workflow là truth độc lập.** ROADMAP §4 là tầng DERIVED, không phải nguồn.
   Khi lệch, workflow thắng (kế thừa DEC-OHANA-05).
2. **Gate là binding layer.** CC propose target + test policy; Wyatt approve
   (`approved_by`/`approved_at`). Không có gate signed → không bind work item.
3. **Anchor convention** (Section 5) làm khoá nối machine-checkable giữa tầng.
4. **Enforcement** pre-commit + CI: `derives_from` trỏ anchor không tồn tại →
   block commit (chi tiết Session 3).
5. **JIT L2.** Spec `docs/tasks/` sinh khi bắt tay code item, KHÔNG preemptive.
   §9.3 cluster table bị BỎ.

Non-goals ADR này: không build skill (Session 3), không tạo gate file
(Session 4), không add anchor (Session 2 — Wyatt).

## Section 3 — F3 resolution: coverage cho fragmented ID  [DECIDED — rule chính]

**Rule đã chốt (Wyatt sign 2026-07-22):**

> Coverage của một `GD?-X` tính theo **aggregate STATUS của TẤT CẢ phase block
> mang `ROADMAP: GD?-X`**, bất kể nằm ở spec nào.
>
> `GD?-X` = **DONE** ⟺ (i) tồn tại ≥1 phase `STATUS: DONE` mang ID này, **VÀ**
> (ii) KHÔNG phase `TODO`/`BLOCKED` nào còn mang ID này.
>
> Phase `CANCELLED`/`SUPERSEDED` **không tính** vào (i) lẫn (ii) — đã retire.

Kiểm trên data thật:
- `GD0-TOOLS`: DONE(01) + BLOCKED(03) → **chưa DONE** ✓ (platform integration
  thật còn kẹt PRE-002).
- `GD0-OBS`: DONE(12) + TODO(03) → **chưa DONE** ✓ (full OTel chưa làm).
- `GD0-DRAFTER`: DONE(13) + TODO(15) → **chưa DONE** ✓ (runtime wiring pending).
- `GD0-FOUNDATION`: DONE(06) + DONE(09) → **DONE** ✓.

**Edge case:**
- ID chỉ toàn `BLOCKED` (vd `GD0-ZALO`): (i) fail ⇒ chưa DONE ✓; và ID này
  `Class: external` nên ngoài mẫu số `internal` — đúng.
- ID 0 phase (vd `GD0-RESIDENCY`): (i) fail ⇒ mãi chưa DONE ⇒ đây chính là F4,
  xử ở Section 4 (không để rule F3 tự đẻ exception).

**Alternative (KHÔNG chọn — ghi lại làm dấu vết):** tách coverage theo Class,
report `internal-DONE` riêng khi mọi phase internal DONE, phase external treo
không ghim. Bị bỏ vì thêm 1 cột L3 phức tạp; rule (ii) cứng là chủ ý — 1 phase
BLOCKED nghĩa là ID chưa xong thật.

## Section 4 — F4 resolution: ADR-only ID  [DECIDED — token phase, gate grep-only]

**Option A (KHÔNG chọn) — Exempt ADR-only ID khỏi phase requirement.**
Đổi §0 coverage rule cho ID thoả bằng ADR ACCEPTED. Cần enumerate danh sách tay
{ `GD0-RESIDENCY` }. Bỏ vì exception list phình + dễ trôi.

**Option B (ĐÃ CHỌN — Wyatt sign 2026-07-22) — Token phase "verify ADR ACCEPTED".**
Tạo **1 phase block** trong một spec compliance (vd spec bao `GD0-PII`/`GD0-SPLIT`
tương lai) mang `ROADMAP: GD0-RESIDENCY`. Acceptance = gate **grep-only**:

> File ADR tồn tại **VÀ** frontmatter `status: ACCEPTED`. **Không content-check**
> (không parse thân ADR, không đánh giá nội dung) — chỉ grep sự tồn tại + trạng
> thái, để gate là hàm tất định của đĩa, không của người đọc.

Coverage semantic **đồng nhất** với Section 3 — mọi ID "DONE qua ≥1 phase DONE",
không nhánh ngoại lệ trong rule F3.

Lý do chọn B: (1) giữ rule Section 3 nguyên vẹn, không exception; (2) bằng chứng
ACCEPTED thành gate chạy được (grep tất định), không phải niềm tin; (3) không
danh sách tay để trôi. Đánh đổi: 1 phase "trống" mỗi ADR-only ID — chấp nhận
được (hiện chỉ 1: `GD0-RESIDENCY`).

## Section 5 — Anchor convention

    Format:    <!-- anchor:<layer>-<section-slug> -->
    Layer:     w (workflow) | g (gate) | r (roadmap)
    Slug:      lowercase kebab-case, bám cấu trúc section
    Invisible: HTML comment — không hiện khi render markdown
    Immutable: KHÔNG rename anchor (mất lịch sử nối). Reorganize section →
               THÊM anchor mới, GIỮ anchor cũ (redirect comment cho phép:
               <!-- anchor:w-old redirect:w-new -->)

Ví dụ:
    <!-- anchor:w-7.1-webhook -->
    <!-- anchor:w-7.4-shop-profile -->
    <!-- anchor:g-gd0-step4 -->
    <!-- anchor:r-4.1-gd0-shops -->

Ràng buộc: mỗi `derives_from: <layer>#<anchor>` phải trỏ tới một anchor tồn tại
ở tầng trên. Dangling = block commit (enforcement).

### 5.1 Exemption: ID Class `scaffold`

**ID Class `scaffold` KHÔNG cần `derives_from`.**

Lý do: scaffold là hạ tầng dựng sẵn (repo chạy được, config loader, seller UI shell). Nó không phải architecture decision → không có WHY ở workflow để neo vào. Ép `derives_from` sẽ đẻ anchor giả ở workflow chỉ để thoả enforcement — làm hỏng chính thứ workflow dùng để nói.

Ranh giới: một ID là scaffold khi **đổi nó không đổi luồng dữ liệu, ranh giới an toàn, hay quyết định kiến trúc** — chỉ đổi cách code được dựng hoặc trình bày. Bất cứ thứ gì chạm 3 trục trên **KHÔNG** phải scaffold, kể cả khi trông giống hạ tầng.

Áp cho: `GD0-BOOTSTRAP`, `GD0-CONFIG`, `GD0-UI`.

`verify_derives` bỏ qua ID `Class: scaffold` khi quét dangling.

**Quan hệ với `Class` §0.1**: `scaffold` là **trục derivation riêng**, không phải giá trị của cột `Class`. ID scaffold giữ `Class: internal` — mẫu số không đổi. Chỉ derivation map đánh dấu `n/a (scaffold)`.

## Section 6 — Migration path (session sau)

- **Session 2** (unblocked khi ADR này signed — ĐÃ signed 2026-07-22): Wyatt tự
  add 7 anchor `w-7.1..w-7.7` vào `backend-workflow.md` §7. CC propose
  `derives_from` cho mỗi ID §4 (trỏ anchor workflow tương ứng). Wyatt review
  batch, sign. ⚠️ CC KHÔNG bắt đầu propose tới khi anchor tồn tại (tránh dangling).
- **Session 3**: Build skill `roadmap-derive` MVP (2 sub: `derive_roadmap`,
  `verify_derives`). Add `.pre-commit-config.yaml` chạy `verify_derives`. Verify
  pipeline pass trên state hiện tại (0 dangling).
- **Session 4**: Dashboard rebuild (Phase→Step→Task tree). Gate file
  `docs/gates/GD0-STEP{1..7}.md` (CC propose YAML frontmatter, Wyatt sign từng
  file `approved_by`/`approved_at`). Token phase F4 (`GD0-RESIDENCY`) land ở đây.

## Section 7 — Rollback plan

- Pipeline vỡ / Wyatt reject giữa chừng → **fallback v6**: ROADMAP v6 vẫn là L1
  hợp lệ (không đụng §4 acceptance/ID).
- Anchor là HTML comment **invisible** → để lại vô hại, không cần gỡ.
- Skill `roadmap-derive` giữ **inactive** (gỡ khỏi pre-commit là đủ).
- ADR này mark `status: SUPERSEDED`. **Không mất data** — không ID nào bị
  rename/xoá, không spec DONE bị đụng.
