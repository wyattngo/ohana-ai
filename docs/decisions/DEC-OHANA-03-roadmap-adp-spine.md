# DEC-OHANA-03 — Roadmap thành xương sống ADP (L1/L2/L3)

| Field | Value |
|---|---|
| Status | **ACCEPTED** |
| Date | 2026-07-19 |
| Decider | Wyatt Ngo (fractional CTO) |
| Author | Claude (main loop) |
| Supersedes | Quyết định ngầm 2026-07-18 trong `PLAN-PhaseTargets-GD0toGD3.md`: *"cố ý KHÔNG chứa phase block máy-đọc nên `adp-status.sh` không đếm"* |
| Liên quan | `docs/ROADMAP.md` (L1) · `docs/ROADMAP-STATUS.md` (L3) · `.claude/tools/adp-roadmap.sh` |

---

## 1. Bối cảnh — vấn đề thật không phải "thiếu chỗ đếm %"

Audit on-disk 2026-07-19 tìm thấy **4 tài liệu lộ trình cùng tồn tại và đã mâu thuẫn**:

| File | Dòng | Vấn đề |
|---|---|---|
| `~/Desktop/Ohana/Roadmap.md` | 447 | v4, được khai canonical, **nằm ngoài repo** |
| `docs/Roadmap.md` | 275 | **hoá thạch v3** — còn chứa tranche/ngân sách mà v4 đã cố ý cắt; lần chạm cuối là `3e07293`, một commit spec-04 không liên quan |
| `docs/tasks/PLAN-PhaseTargets-GD0toGD3.md` | — | lớp acceptance |
| `docs/tasks/PLAN-TechLead-Decomposition-Roadmap.md` | — | lớp WBS + audit |

Cả hai file PLAN trỏ tới **"Roadmap v3" bằng đường dẫn tuyệt đối trên Desktop** — sai version, ngoài repo, chỉ chạy trên một máy. Người thứ hai clone repo sẽ đọc bản 275 dòng và tin đó là lộ trình.

Đồng thời **không có khoá nối** giữa roadmap và ADP: roadmap không có ID, phase block không có trường trỏ ngược. Vì vậy không máy nào tính được coverage, và không cơ chế nào phát hiện được kế hoạch và thực thi đã rời nhau.

## 2. Quyết định

**Roadmap trở thành xương sống ADP theo mô hình 3 tầng, mỗi tầng một chủ sở hữu.**

| Tầng | File | Writer | Chứa | Không chứa |
|---|---|---|---|---|
| L1 | `docs/ROADMAP.md` | **người** (Wyatt) | ý định, lý do, ID bền, acceptance | STATUS, %, phase block |
| L2 | `docs/tasks/NN-Task-*.md` | senior-engineer → frozen | phase block + `ROADMAP: <id>` | chiến lược |
| L3 | `docs/ROADMAP-STATUS.md` | **máy** (`adp-roadmap.sh`) | coverage, uncovered, unplanned | — (sinh ra, không sửa tay) |

Kèm theo:
1. **Khoá nối** — trường `ROADMAP: <id>` bắt buộc trong mọi ADP phase block. Đã chèn cho 34/34 block hiện có.
2. **ID bền, append-only** — 35 work item. Mục bỏ đi đánh dấu `RETIRED` kèm DEC, **không xoá dòng**.
3. **Ba lớp mẫu số** — `internal` (mẫu số của mục tiêu 100%) / `external` (chờ bên thứ ba, đếm riêng) / `out-of-scope` (GĐ4, không đếm).
4. **Lịch sử mẫu số** — `docs/.roadmap-denominator.log`. Mẫu số internal giảm mà không có DEC = cảnh báo gian lận chỉ số.
5. **Hợp nhất** — bản v3 hoá thạch + 2 file PLAN companion vào `docs/archive/`. Còn **một** nguồn.
6. **L4** — `adp-checkpoint.sh` sinh lại L3 sau khi stamp EVIDENCE. Checkpoint **không bao giờ ghi vào L1**.

## 3. Vì sao đảo quyết định cũ

Quyết định 2026-07-18 giữ tài liệu kế hoạch ra khỏi bộ đếm là **đúng với lý do của nó**: `adp-status.sh` đếm cam kết đã đóng băng, roadmap là ý định còn mềm; trộn vào một mẫu số làm mất phân biệt "đã ký, đang nợ" với "mới nghĩ, chưa chắc làm".

Lý do đó **vẫn đúng và được giữ nguyên** — bằng cách tách L3 khỏi `adp-status.sh` thay vì nhét roadmap vào nó. Hai bộ đếm, hai câu hỏi khác nhau:

- `adp-status.sh` → *"phase đã ký đi tới đâu?"* (21/34)
- `adp-roadmap.sh` → *"kế hoạch đã phủ tới đâu?"* (internal 8/25)

## 4. Ràng buộc thiết kế bắt buộc giữ

**L1 nằm NGOÀI spec-lock.** `adp_spec_lock_verify` chỉ khoá `SPEC_DIR`. Nếu kéo L1 vào vùng diff-bound, mọi lần re-plan giữa sprint sẽ bị checkpoint REFUSE vì DRIFT — máy cấm người đổi ý. Ý định phải sửa được mà không xin phép. **Đây là ranh giới, không phải sơ suất.**

**L1 không được có trường STATUS.** Giá trị lớn nhất của L1 là những phán đoán *không có trạng thái* — guardrails §2.3, "vì sao VLM chứ không CLIP", "KHÔNG dynamic routing", danh sách reject. Khi một file bị máy quản lý, nó bị ép dần về hình dạng checklist và phần lý luận teo đi trước tiên. Trạng thái đi ra L3, không đi vào L1.

## 5. "100% Roadmap" nghĩa là gì

**Mẫu số = `internal`.** Tại thời điểm ký: **8/25 (32%)**.

Con số này **thấp hơn nhiều** so với 21/34 (61%) của `adp-status.sh` — và đó là đúng, không phải regression. 34 là mẫu số cục bộ của những spec đã viết; 25 là mẫu số thật của kế hoạch. Số tụt vì mẫu số đúng lên, không phải vì tiến độ xấu đi.

**Không gộp `external` vào 100%.** 10 mục chờ Tân / Meta / audit firm / provider. Gộp vào thì chỉ số không bao giờ chạm 100% và sẽ bị bỏ qua sau vài tuần.

**GĐ4 không đếm** — roadmap tự khai ngoài scope, kiến trúc khác bản chất.

## 6. Hệ quả

**Được:**
- Một nguồn lộ trình thay vì bốn.
- Phát hiện drift **hai chiều**: `uncovered` (kế hoạch chưa ai nhận) và `unplanned` (đang làm việc ngoài kế hoạch). Trước đây không cơ chế nào thấy chiều thứ hai.
- Chỉ số 100% có mẫu số phòng thủ được, có lịch sử, khó gian lận.

**Mất / phải trả:**
- Mọi spec mới **bắt buộc** khai `ROADMAP:` — thêm một bước.
- ID sai lúc gán sẽ đẻ ra coverage sai; sửa ID = mất lịch sử đối chiếu.
- L1 và L2 vẫn có thể lệch về *nội dung* (ID đúng nhưng phase làm việc khác) — máy không bắt được, chỉ người review bắt được.

**Phát hiện ngay khi bật:** `GD0-RESIDENCY` hiện **uncovered** dù ADR PRE-007 đã ACCEPTED — công việc thật đã xong nhưng **không chạy dưới một ADP phase nào**. Đây chính là loại lỗ hổng truy vết mà L3 sinh ra để thấy. Chưa xử lý; ghi nhận.

## 7. Việc còn lại cho Wyatt (không tự làm được)

1. **`~/Desktop/Ohana/Roadmap.md` chưa đụng tới** — file cá nhân, không tự ý sửa. Nó vẫn là bản v4 447 dòng và vẫn tự khai canonical. **Nếu để nguyên, drift tái lập đúng như cũ.** Đề nghị: xoá, hoặc thay bằng một dòng trỏ về `ohana-ai/docs/ROADMAP.md`.
2. **Ký RISK tier** cho `GD0-RESIDENCY`: hồi tố một phase, hay chấp nhận nó đứng ngoài ADP vĩnh viễn.
3. Xác nhận cách phân lớp `internal`/`external` ở L1 §4 — đặc biệt `GD1-PAY`/`GD1-SHIP` (xếp external vì phụ thuộc onboarding provider/carrier; có thể tranh luận là internal vì code là của ta).
