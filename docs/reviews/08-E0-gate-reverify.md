# Re-verify GATE_FULL — spec 08 phase E0 (ISSUE-019)

**Vì sao có file này.** Checkpoint E0 (`8ba4fef`) stamp `GATE_FULL: PASS`, nhưng bước
`ruff check .` trong đó đọc `.ruff_cache` cũ và trả PASS giả. Ba bước còn lại
(pytest / mypy / ruff format) hợp lệ. EVIDENCE đã stamp không thể sửa lại — thay vì
viết đè lịch sử, ghi bản re-verify này và trỏ từ ISSUE-019 sang.

**Không re-checkpoint E0.** `adp-checkpoint.sh` chỉ chạy cho phase IN_PROGRESS; lật E0
về IN_PROGRESS để chạy lại sẽ tạo một checkpoint thứ hai cho cùng một phase và làm hỏng
đúng thứ spine đang bảo vệ — quan hệ 1-1 giữa phase và EVIDENCE. Bản chất vấn đề cũng
không nằm ở code của E0: 4 lỗi bị che thuộc `agent/providers/openai_embedder.py` và
`tests/test_tenant_isolation.py`, cả hai land từ spec 01/02, ngoài ALLOWED_FILES của E0.

## Chạy lại, cache đã xoá, `--no-cache` tường minh

Lệnh: `GATE_FULL` của E0, thêm `--no-cache` ở cả hai bước ruff.
Thời điểm: 2026-07-19, sau khi vá 4 lỗi I001.

```
pytest        exit=0   121 passed, 3 deselected
mypy          exit=0   Success: no issues found in 38 source files
ruff check    exit=0   All checks passed!     (--no-cache)
ruff format   exit=0   73 files already formatted   (--no-cache)
```

**Kết luận: E0 PASS THẬT.** Nội dung E0 chưa từng sai — chỉ có lời khai về nó từng dựa
một phần vào cache. Sau khi vá 4 lỗi kế thừa từ spec 01/02, cả 4 bước đều xanh dưới điều
kiện tái lập được.

## Cái gì đổi để không lặp lại

1. `pyproject.toml` pin `ruff==0.15.22` (không `>=`).
2. `--no-cache` vào mọi bước ruff: `.github/workflows/ci.yml`, `CLAUDE.md` §1,
   `GATE_FULL` của spec 08 E1/E2.
3. `CLAUDE.md` §4 ghi bẫy này cạnh các bẫy env đã trả giá.

Không đụng GATE_FULL của các spec đã DONE — sửa spec đã ký để làm đẹp số liệu quá khứ
là đúng thứ ADP dựng lên để chặn.

## Còn nợ

- `mypy>=1.10` và `pytest>=8.0` vẫn chưa pin. Cùng lớp rủi ro, chưa ai nhận.
- Trạng thái CI thật chưa ai xác nhận — suy luận từ config là CI đã đỏ (runner không
  restore `.ruff_cache`), nhưng **chưa mở tab Actions để nhìn**. Đừng khai là đã biết.
