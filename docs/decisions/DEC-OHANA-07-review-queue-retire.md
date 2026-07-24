# DEC-OHANA-07 — Retire `REVIEW_QUEUE.md`; auto-verdict là gate DUY NHẤT cho RISK medium/low

- **Date:** 2026-07-24
- **Status:** ACCEPTED
- **Signed-by:** Wyatt · 2026-07-24
- **Supersedes:**
  - `DEC-OHANA-01-web-framework.md:196` (*"P0/P1 (medium): … + async REVIEW_QUEUE.md"*)
  - Enqueue block trong `.claude/tools/adp-checkpoint.sh:385-391` + `git add` L411 + NEXT message L418+427
- **Related:** DEC-OHANA-06 (kill tick syntax), DEC-OHANA-03 (roadmap 3 tầng), WAIVER-001.

---

## Context

`docs/memory/REVIEW_QUEUE.md` được dựng theo v1.3 ADP: mọi checkpoint tier medium/low append 1 dòng `[ ]`; Wyatt review batch async rồi tick `[x]`. Ý đồ: giữ tốc độ ship (auto-verdict qua Haiku) mà vẫn có kiểm tra hai lớp.

**Đo tại 2026-07-24 (`git rev-parse HEAD`):**

```
grep -c '^- \[ \]' docs/memory/REVIEW_QUEUE.md   → 32
grep -c '^- \[x\]' docs/memory/REVIEW_QUEUE.md   → 0
grep -o 'judge=[A-Z_]*' | sort | uniq -c         → 31 APPROVE (1 skip docs-only)
Oldest entry: 2026-07-16T22:48
```

**Sự thật đã thấy:**

1. **8 ngày, 0 tick.** Không phải vì tick khó — gõ `[x]` là một phím. Nguyên nhân duy nhất giải thích được: **không có khoảnh khắc nào mà "chưa review" thì chặn việc gì.** Queue chỉ append; checkpoint không đọc lại; không hook, script hay CI nào block khi entry chưa tick. Điều gì không chặn thì không được làm.
2. **Auto-verdict đã chạy trên toàn bộ 32 phase và pass 31/32.** Phase còn lại là `skip(docs-only)` — cũng là quyết định đúng. Không có case nào để Wyatt "review lại" phát hiện điều Haiku miss.
3. **32 entry mang metadata giá trị** (`bound=<diff_sha256>`, `revert:` command) — đây là **audit trail có ích**, không phải rác. Xoá nội dung là mất record của WAIVER-001 (22 phase pre-CI-xanh đều ở đây).

**Vấn đề cốt lõi:** hai vai xung đột trong cùng một file.

- **Vai audit trail** (append-only, `bound=`, `revert:`) — có giá trị, đang được dùng nếu ai muốn revert.
- **Vai review-queue** (ô `[ ]` → `[x]`, checkbox state) — đã chết trong 8 ngày, không cơ chế nào phục sinh được.

Cùng lỗi kiến trúc như 41 ô tick ở `docs/gates/` mà DEC-OHANA-06 vừa xử: **state ở tầng không có gate**.

## Options considered

1. **(a) Cho răng — checkpoint từ chối mở spec mới khi tồn > N entry chưa review.**
   - *Pros:* tạo ra chính "khoảnh khắc chặn" mà queue đang thiếu.
   - *Cons:* (i) 32/32 hiện đang APPROVE → cửa mới sẽ mở ngay khi ai tick hàng loạt để unblock, tick trở thành nghi thức không nội dung; (ii) nếu Wyatt bận, cửa này chặn cả ship khi không có gì để phát hiện; (iii) tăng chi phí nhận thức mà phần lớn thời gian không sinh finding — Haiku đã chạy sẵn.

2. **(b) Xoá `[ ]` + DEC ghi nhận auto-verdict là gate DUY NHẤT cho medium/low. ← CHỌN**
   - *Pros:* tôn trọng sự thật đã đo (Wyatt không review batch, mà cũng không cần vì Haiku pass sạch). Không thêm nghi thức. RISK:high vẫn giữ Wyatt sync review — cửa duy nhất Wyatt còn dùng thật.
   - *Cons:* mất khả năng "hai lớp mắt" ngay cả trong lý thuyết. Chấp nhận vì lý thuyết đó chưa từng chuyển thành thực hành.

3. **(c) Giữ file, biến thành pure audit trail (xoá cú pháp `[ ]`, giữ metadata).**
   - Tương đương (b) về nghĩa gate; khác về hình thức file. **Chọn (b) rồi làm phần audit của (c)**: xoá file cũ (giữ trong git history đủ để revert), thay bằng dòng thông báo trong DEC + trỏ `git log` làm audit trail.

## Quyết định

**Option (b).** Auto-verdict (Haiku qua `.claude/tools/adp-review.sh`) là **gate DUY NHẤT** cho RISK medium và low. RISK high **KHÔNG đổi** — vẫn cần Wyatt sync review diff trước checkpoint (v1.3 ADP giữ nguyên).

### Cụ thể

- **Xoá `docs/memory/REVIEW_QUEUE.md`** khỏi working tree. File còn nguyên trong git history (branch `main` trước commit này) — audit trail cho 32 phase ký 16/07–23/07 vẫn accessible qua `git show <commit>:docs/memory/REVIEW_QUEUE.md`.
- **Gỡ enqueue block** khỏi `.claude/tools/adp-checkpoint.sh` (L385-391, L411 git-add, L418 print, L427 NEXT-msg).
- **Patch `DEC-OHANA-01:196`** — bỏ mệnh đề "+ async REVIEW_QUEUE.md".
- **Giữ nguyên** file historical: `docs/tasks/02-…md`, `docs/memory/SESSION_LOG.md`, `docs/briefs/brief-08-…md`. Chúng là snapshot lịch sử; sửa = viết lại lịch sử.

## Waive cái gì — nói chính xác

| | |
|---|---|
| **ĐƯỢC waive** | Yêu cầu Wyatt review async từng phase medium/low. Không còn nghi thức tick. |
| **ĐƯỢC waive** | Kỳ vọng "hai lớp mắt" cho medium/low. Chỉ còn một lớp (Haiku). Đây là sự thật đã tồn tại từ 16/07, DEC này chỉ ghi nhận. |
| **KHÔNG waive** | RISK high vẫn cần Wyatt sync review diff trước checkpoint. Đường bypass duy nhất là `RISK_WAIVER` do chính Wyatt viết. |
| **KHÔNG waive** | Auto-verdict phải chạy thực sự. `REVIEW: PASS ref=<artifact>` với `diff_sha256` bound vẫn là điều kiện cứng của `adp-checkpoint.sh` — DEC này KHÔNG hạ chất lượng gate đó. |
| **KHÔNG waive** | Khi Haiku REJECT hoặc `judge=NEEDS_REVIEW`, checkpoint REFUSE — không có đường "queue để xem sau". Reject là chặn ngay, không phải để lại. |
| **KHÔNG waive** | Audit trail có commit hash + revert command. Metadata của 32 entry lịch sử vẫn accessible qua `git log --all -- docs/memory/REVIEW_QUEUE.md` + `git show`. |

## Consequences

- **Tốc độ:** checkpoint medium/low không đổi (queue trước đây cũng chưa từng chặn) — thay đổi là nghĩa, không phải tempo.
- **Rủi ro:** nếu Haiku miss một class bug đặc thù Ohana (dạng "silent-wrong retrieval" mà spec `ai-agent-invariants.md §7` cảnh báo) → không còn cửa thứ hai bắt. Mitigate: khi phát hiện Haiku miss thật, đó là tín hiệu **nâng RISK tier lên high** cho lớp phase đó, không phải hồi sinh REVIEW_QUEUE. Nâng tier là cửa mà Wyatt vẫn dùng thật.
- **Audit trail:** nếu cần revert 1 phase pre-DEC-007, `git log --all --oneline -- docs/memory/REVIEW_QUEUE.md` cho commit gốc, `git show <SHA>:docs/memory/REVIEW_QUEUE.md | grep <spec-phase>` cho dòng revert. Không mất capability, chỉ chuyển sang thao tác cấp thấp hơn.
- **DEC-OHANA-01:196** patch cùng commit thi công. Brief lịch sử (`brief-08-*`, spec 02) giữ nguyên — chúng viết đúng cơ chế **tại thời điểm sinh**; sửa ngược = rewrite lịch sử.

## Còn treo (không thuộc DEC này)

- **Nếu Haiku pass sạch quá đều** (31/32 APPROVE, 0 tìm ra bug thật) — đó có thể là (i) code đang đúng thật, hoặc (ii) rubric Haiku quá dễ. Phân biệt cần một injection test: cố tình checkpoint 1 phase với bug đã biết (silent-wrong retrieval / identity từ body), xem Haiku có bắt không. Task này KHÔNG thuộc DEC-007 vì nó đo chất lượng của **auto-verdict**, không phải câu hỏi "cần cửa cho REVIEW không". Đưa lên sau khi có dịp thật.
- **DEC-001/002/003 PROPOSED** — vẫn treo, cần Wyatt ký trực tiếp.

---

## Verify

**Trước commit:**
```
grep -c '^- \[' docs/memory/REVIEW_QUEUE.md                              → 32
grep -c 'REVIEW_QUEUE' .claude/tools/adp-checkpoint.sh                    → 4
grep -c 'async REVIEW_QUEUE' docs/decisions/DEC-OHANA-01-web-framework.md → 1
```

**Sau commit chuỗi DEC-007:**
```
test -f docs/memory/REVIEW_QUEUE.md                                       → 1 (not found)
grep -c 'REVIEW_QUEUE' .claude/tools/adp-checkpoint.sh                    → 0
grep -c 'async REVIEW_QUEUE' docs/decisions/DEC-OHANA-01-web-framework.md → 0
git log --all --oneline -- docs/memory/REVIEW_QUEUE.md | head -1          → commit gốc còn accessible
python3 scripts/roadmap_derive.py verify                                   → exit 0
pytest -q                                                                  → 252 passed
```
