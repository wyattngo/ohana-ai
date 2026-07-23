# DEC-OHANA-06 — Bỏ cú pháp `[ ]` khỏi 9 gate đã ký; giữ nguyên nội dung

- **Date:** 2026-07-24
- **Status:** ACCEPTED
- **Signed-by:** Wyatt · 2026-07-24
- **Supersedes semantic of:** `docs/gates/README.md:44` (*"đóng gate = mọi ô `[ ]` tick"*).
- **Related:** DEC-OHANA-03 (roadmap 3 tầng), DEC-OHANA-04 (WAIVER-001), ADR `2026-07-22-derivation-pipeline`.

---

## Context

`docs/gates/GD0-STEP1..9.md` được ký `approved_by: wyatt` ngày 2026-07-23. Mỗi file có section `## Tests` gồm nhiều dòng `- [ ] ...` mô tả *hành vi đo được*. `docs/gates/README.md:29,44` định nghĩa "đóng gate" = *"mọi ô `[ ]` trong Tests tick xong bằng test chạy thật"*.

**Đo tại 2026-07-24 (`git rev-parse HEAD` = `131dda0`):**

```
grep -h '^- \[' docs/gates/GD0-STEP*.md | sort | uniq -c
    → 41 dòng, 0 dòng [x]
```

**Chi phí thực của cú pháp này:**

1. **41 ô mang state trong một tầng thiết kế để chứa ý định bất biến.** ADR `2026-07-22` định nghĩa `docs/gates/` là tầng **derivation** — Wyatt ký ý định TRƯỚC khi code. Ô `[ ]` là affordance của *tiến độ*, không phải của ý định. Hai vai xung đột trong cùng một dòng.
2. **`GATE:` trong phase block là "done" chạy được.** `docs/tasks/16-Task-OhanaAISeller-PIIFilter.md` phase A0 mang `GATE: .venv/bin/python -m pytest tests/test_pii_filter.py -x -q` — REFUSE khi đỏ. Ô `[ ]` trong `gates/GD0-STEP2.md` là **bản sao gõ tay** của cùng ý định đó, chỉ khác là không REFUSE.
3. **`.adp-red-proof.json` phủ 6 phase RISK:high** (test-first cơ giới hoá). 34/41 phase medium+low **không cần red-proof cơ giới** — ô `[ ]` không giải bài toán đó, vì medium/low ADP cấp không đòi test viết trước. Cùng cú pháp diễn hai nghĩa khác nhau, kết quả cả hai đều rỗng.
4. **`tests_done/tests_total` rò rỉ lên `docs/roadmap-dashboard.html` KPI** — dashboard là VIEW theo hợp đồng L3, KHÔNG được hiển thị số máy sinh từ affordance state có thể sửa tay. Đây là vi phạm DEC-OHANA-03 phía render.

**Verify ràng buộc "không phải bản sao":**

```
grep -h '^- \[ \]' docs/gates/GD0-STEP*.md | wc -l   → 41
grep -c '^GATE:' docs/tasks/*.md                    → 41 (mỗi spec ≥ 1)
```

Nhưng ánh xạ *không* toàn phần. Nội dung gate ứng với work item **chưa có spec** (`GD0-COALESCE`, `GD0-METER`, `GD0-INTENT`, `GD0-WINDOW`) tồn tại **chỉ ở gate**. Ví dụ `GD0-STEP3.md`:

```
- [ ] 2 approve đồng thời ⇒ 1 thành công, 1 nhận rows-affected = 0 (optimistic lock)
- [ ] Hoán vị thứ tự rule ⇒ intent chọn ra KHÔNG đổi
- [ ] Worker crash giữa lúc debounce ⇒ scheduler vẫn bắn (đọc lại từ DB)
- [ ] Pre-charge reserve trước call; reconcile giải phóng phần dư
- [ ] PRE-010 C4 — script đo FN rate trên tập gán nhãn ≥200 tin, ra con số
```

Xoá thẳng section = mất ý định của Wyatt. **Giữ nội dung, giết ô vuông.**

## Options considered

1. **Xoá section `## Tests` khỏi 9 gate + regen L3.**
   - *Pros:* dashboard sạch; hết cú pháp state trong tầng ý định.
   - *Cons:* mất 5 dòng ý định cho `GD0-COALESCE/METER/INTENT/WINDOW` — chưa có spec để hứng. Vi phạm chính nguyên tắc *"L2 sinh JIT"* của ADR 2026-07-22 nếu ép sinh spec chỉ để chứa các dòng đó.
2. **Viết `adp-gate.sh` chạy pytest theo node ID và auto-tick.**
   - *Pros:* zero self-cert cho đường "test đã tồn tại".
   - *Cons:* 34/41 dòng test **chưa tồn tại** — công cụ sẽ báo đỏ vĩnh viễn cho việc chưa tới lượt làm. Và L3 dashboard hợp đồng KHÔNG có ô tick (DEC-OHANA-03) ⇒ output không có chỗ đọc.
3. **Đổi cú pháp `- [ ] X` → `- X` + rename section `## Tests` → `## Test policy`. ← CHỌN**
   - *Pros:* Nội dung được giữ nguyên (Wyatt đã ký ý định đó); cú pháp phát tín hiệu đúng — *"đây là hợp đồng, không phải checklist"*. Tooling `roadmap_derive.py` không còn parse `tests_open/tests_done` ⇒ dashboard KPI hết nhắc số đó ⇒ vi phạm L3 tự chết.
   - *Cons:* Sửa artifact đã ký — cần DEC này công khai lý do, để không ai đọc "đã ký" hẹp hơn hoặc rộng hơn nó đáng.

## Quyết định

**Option 3.**

- 9 file `docs/gates/GD0-STEP*.md`: đổi cú pháp `- [ ] <câu>` → `- <câu>`, đổi tên section `## Tests` → `## Test policy`. **Không sửa một chữ nào trong 41 câu nội dung.**
- `docs/gates/README.md:29,44`: cập nhật semantic *"đóng gate"* — xem §Consequences.
- `scripts/roadmap_derive.py`: bỏ field `tests_open`/`tests_done` trên `Gate`, bỏ regex `TEST_OPEN_RE`/`TEST_DONE_RE`, bỏ print `tests`.
- `scripts/roadmap_dashboard.py` + `.tpl.html`: bỏ hiển thị `tests_done/tests_total` (KPI card + pill + tests block).

## Waive cái gì — nói chính xác

| | |
|---|---|
| **ĐƯỢC waive** | Yêu cầu ở `README:44` rằng "đóng gate = mọi ô `[ ]` tick". Ô không còn tồn tại. |
| **KHÔNG waive** | 41 câu nội dung. Chúng vẫn là **hợp đồng đã ký** — Wyatt đã ký 2026-07-23. |
| **KHÔNG waive** | Yêu cầu spec có phase RISK:high viết test ĐỎ trước impl. `.adp-red-proof.json` vẫn là gate. |
| **KHÔNG waive** | Yêu cầu `GATE:` mỗi phase phải chạy pass trước checkpoint. Đây mới là "done" chạy được, không phải ô tick. |
| **KHÔNG waive** | Ràng buộc L3 dashboard là VIEW (DEC-OHANA-03). Bỏ `tests_done/total` khỏi KPI là làm sạch một vi phạm, không phải hạ tiêu chuẩn. |

## Consequences

**Nghĩa mới của "đóng gate":** một work item bound gate `GD0-STEPn` được coi là **đã đóng** khi mọi phase L2 dẫn xuất từ nó có `STATUS: DONE` (qua `adp-checkpoint.sh` — nghĩa là `GATE:` pass thật + EVIDENCE stamp + hash khớp diff). Section `## Test policy` KHÔNG có machine state, nó là input cho tác giả L2 khi sinh spec JIT: mỗi câu nên trở thành 1 assertion trong `GATE:` của phase tương ứng.

**Nghĩa mới của "ký gate":** Wyatt ký = *"đây đúng là điều kiện đo được tôi muốn cho sub-step §7.n"*. Bất biến sau khi ký. Sửa nội dung câu = cần DEC riêng, không patch lặng.

**Hệ quả trên tooling:**

- `roadmap_dashboard.py` sau commit: KPI `steps_signed/steps` giữ (đo ý định đã ký), `tests_done/total` bỏ (đo affordance đã chết).
- `roadmap_derive.py verify` không đổi — chỉ gỡ field không dùng.
- Không có consumer nào khác của `tests_done/tests_total` (verified 2026-07-24: `grep -rn "tests_done\|tests_total" --include='*.sh' --include='*.py' --include='*.html'` → chỉ 3 file thuộc scope commit này).

**Hệ quả trên phase kế tiếp:**

- Spec 15 (RuntimeWiring) và spec chưa tồn tại cho `GD0-COALESCE/METER/INTENT/WINDOW` khi sinh JIT phải **đọc `## Test policy` của gate tương ứng** và chuyển từng câu thành `GATE:` assertion. Đây là cách nội dung được bảo toàn về nơi chạy được.
- Ai viết spec mà bỏ qua `Test policy` của gate mình bind = làm mất ý định Wyatt đã ký. Reviewer gate phải bắt.

**Rủi ro đã cân nhắc:**

- *"Nội dung không có state → không ai nhớ kiểm."* — Đúng phần hình thức, nhưng đây là bài đúng. State không giải bài "ai kiểm", nó chỉ chuyển bài đó thành "ai tick". Bài "ai kiểm" chỉ giải bằng cơ chế L2 spec tiêu thụ nội dung (JIT), không phải bằng thêm ô nhấn.

## Còn treo (không thuộc DEC này)

- **`KNOWN_ISSUES.md:7` header rot** (index tự khai mâu thuẫn entry `:161`). Vấn đề riêng, không phải chi phí cú pháp tick. Sẽ được xử ở DEC khác nếu Wyatt muốn.
- **`REVIEW_QUEUE.md` 32/32 chưa tick từ 16/07.** Phương án (a) checkpoint từ chối / (b) xoá + DEC nhận auto-verdict là gate duy nhất — chờ Wyatt quyết. KHÔNG gộp vào DEC này vì nó là câu hỏi khác: *"cần cửa cho REVIEW không?"* — không phải *"cần cửa cho TESTS ở tầng ý định không?"*.
- **`DEC-001/002/003` mang `PROPOSED` trong khi code đã thực thi.** Ký hồi tố cần Wyatt sign trực tiếp, không phải scope của DEC-006.

---

## Verify

**Trước commit:**
```
grep -h '^- \[' docs/gates/GD0-STEP*.md | wc -l                → 41
grep -c 'tests_done\|tests_total' scripts/roadmap_dashboard.py → 4
grep -c 'tests_done\|tests_total' scripts/roadmap_dashboard.tpl.html → 4
grep -c 'tests_open\|tests_done' scripts/roadmap_derive.py     → 4
```

**Sau commit chuỗi DEC-006 này:**
```
grep -h '^- \[' docs/gates/GD0-STEP*.md | wc -l                → 0
grep -h '^- ' docs/gates/GD0-STEP*.md | wc -l                  → ≥ 41 (nội dung giữ)
grep -c 'tests_done\|tests_total' scripts/roadmap_dashboard.py → 0
grep -c 'tests_done\|tests_total' scripts/roadmap_dashboard.tpl.html → 0
grep -c 'tests_open\|tests_done' scripts/roadmap_derive.py     → 0
python3 scripts/roadmap_derive.py verify                       → exit 0
pytest -q                                                       → xanh
```
