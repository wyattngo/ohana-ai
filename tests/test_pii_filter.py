"""Gate cho PII redactor (spec 16 A0 · gate `GD0-STEP2` ô Tests #1).

Phạm vi CÓ CHỦ Ý hẹp: file này kiểm **hàm thuần** `agent.pii.redact`. Câu hỏi
*"filter có thật sự nằm trên đường đi tới LLM không"* là của B0 và phải được trả lời
bằng test đi **qua endpoint**, KHÔNG bằng cách gọi thẳng `redact()`. Trộn hai câu hỏi
vào cùng một file sẽ tạo cảm giác an toàn sai: regex xanh chứng minh regex đúng, nó
KHÔNG chứng minh có ai gọi regex đó.

Nguồn danh sách 5 lớp PII: `docs/backend-workflow.md` §5 ("PII filter kỹ thuật").
"""

from __future__ import annotations

import pytest

from agent.pii import RedactionResult, redact

# ---------------------------------------------------------------------------------------
# Lớp 1-5: bắt đúng thứ phải bắt
# ---------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "raw",
    [
        "0912345678",  # 10 số, prefix 09
        "0387654321",  # 03
        "0512345678",  # 05
        "0798765432",  # 07
        "0812345678",  # 08
        "09123456789",  # 11 số (dải cũ)
    ],
)
def test_phone_vn_redacted(raw: str) -> None:
    out = redact(f"sđt em là {raw} nhé")
    assert raw not in out.text
    assert "[SĐT]" in out.text
    assert out.hits == {"phone": 1}


@pytest.mark.parametrize("raw", ["123456789", "079301234567"])
def test_cccd_cmnd_redacted(raw: str) -> None:
    """CMND 9 số và CCCD 12 số — cả hai đều là định danh nhà nước."""
    out = redact(f"cccd {raw}")
    assert raw not in out.text
    assert "[CCCD]" in out.text
    assert out.hits == {"national_id": 1}


@pytest.mark.parametrize("raw", ["12345678", "1234567890", "1234567890123456789"])
def test_bank_account_redacted(raw: str) -> None:
    """Heuristic 8-19 số liên tiếp. `1234567890` = 10 số nhưng KHÔNG có prefix di động
    ⇒ rơi về STK chứ không phải SĐT — đây là ca phân định dễ sai nhất."""
    out = redact(f"stk {raw} vietcombank")
    assert raw not in out.text
    assert "[STK]" in out.text
    assert out.hits == {"bank_account": 1}


def test_email_redacted() -> None:
    out = redact("mail em: khach.hang+shop@gmail.com ạ")
    assert "khach.hang+shop@gmail.com" not in out.text
    assert "[EMAIL]" in out.text
    assert out.hits == {"email": 1}


@pytest.mark.parametrize(
    "raw",
    [
        "123 Nguyễn Huệ",
        "45A Lê Lợi",
        "12/3 Trần Hưng Đạo",
        "88 đường Lê Duẩn",
        "2026 đường Nguyễn Huệ",  # số trùng dạng năm NHƯNG có từ khoá đường ⇒ vẫn là địa chỉ
    ],
)
def test_address_redacted(raw: str) -> None:
    out = redact(f"giao tới {raw} giúp em")
    assert "[ĐỊA_CHỈ]" in out.text
    assert out.hits == {"address": 1}


@pytest.mark.parametrize("raw", ["12 ngõ Huế", "2026 đường A", "1950 đường Nguyễn Huệ"])
def test_street_keyword_is_strong_enough_signal(raw: str) -> None:
    """Có từ khoá đường/ngõ/hẻm ⇒ nới hai ràng buộc, có chủ ý.

    `đường A` / `ngõ Huế` là dạng tên đường VN có thật (khu công nghiệp, quận mới), nên
    nhánh này nhận tên **1 từ** — nhánh không-từ-khoá vẫn đòi ≥2 từ. Và từ khoá lấn át
    phỏng đoán năm: `1950 đường Nguyễn Huệ` là địa chỉ, dù `1950 Nguyễn Huệ` thì không.

    Ghim ở đây vì nới ràng buộc mà không có test là nới không ai thấy — lần refactor sau
    sẽ có người siết lại rồi phá đúng những địa chỉ này mà suite vẫn xanh.
    """
    out = redact(f"giao tới {raw} nhé")
    assert "[ĐỊA_CHỈ]" in out.text
    assert out.hits == {"address": 1}


@pytest.mark.parametrize(
    "raw",
    [
        "năm 2026 Nguyễn Huệ khai trương",
        "sinh năm 1999 Nguyễn Văn Nam",
        "shop mở từ 2020 Sài Gòn nhé",
        "đơn từ năm 2024 Nguyễn Văn A đặt",
    ],
)
def test_year_before_proper_noun_is_not_an_address(raw: str) -> None:
    """Số 4 chữ số dải 1900-2099 đứng một mình là NĂM, không phải số nhà.

    Không chặn thì "sinh năm 1999 Nguyễn Văn Nam" thành "sinh năm [ĐỊA_CHỈ]" — redactor
    nuốt cả vế sau, câu mất nghĩa, nháp gửi khách bị méo. Hỏng theo kiểu im lặng: không
    exception, không test nào khác đỏ, chỉ có seller đọc nháp mới thấy.
    """
    out = redact(raw)
    assert out.text == raw
    assert out.hits == {}


# ---------------------------------------------------------------------------------------
# Thứ KHÔNG được đụng — lọc quá tay làm hỏng ngữ cảnh ⇒ draft sai (§4 trục user-trust)
# ---------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "raw",
    [
        "cho em 2 cái nhé",
        "giá 350k thôi ạ",
        "còn size M không shop",
        "đơn 150000 đồng",
        "5 cái áo màu đen",
    ],
)
def test_non_pii_untouched(raw: str) -> None:
    out = redact(raw)
    assert out.text == raw
    assert out.hits == {}


def test_shape_preserved_not_blanked() -> None:
    """Thay bằng token có nhãn, KHÔNG xoá trắng — câu phải còn đọc được để LLM soạn nháp."""
    out = redact("gọi em 0912345678 nha shop")
    assert out.text == "gọi em [SĐT] nha shop"


# ---------------------------------------------------------------------------------------
# Tính tất định — hits, hoán vị, idempotent
# ---------------------------------------------------------------------------------------


def test_hits_counts_by_type_not_text() -> None:
    """`hits` là thứ destination-log sẽ ghi. Nó đếm theo LOẠI và KHÔNG mang text —
    log để audit mà lại chứa PII thì chính log thành chỗ rò (§4 RED FLAG)."""
    out = redact("0912345678 và 0987654321, mail a@b.vn")
    assert out.hits == {"phone": 2, "email": 1}
    for value in out.hits.values():
        assert isinstance(value, int)


def test_result_order_independent_of_position_in_sentence() -> None:
    """Kết quả không phụ thuộc thứ tự PII xuất hiện trong câu — cùng tập vào, cùng `hits`."""
    parts = ["0912345678", "a@b.vn", "123456789", "12345678", "123 Nguyễn Huệ"]
    first = redact(" ; ".join(parts))
    second = redact(" ; ".join(reversed(parts)))
    assert first.hits == second.hits


def test_idempotent() -> None:
    """Chạy hai lần cho cùng kết quả — token thay thế không được tự bị redact lần nữa."""
    once = redact("sđt 0912345678, mail a@b.vn, nhà 123 Nguyễn Huệ")
    twice = redact(once.text)
    assert twice.text == once.text
    assert twice.hits == {}


def test_long_digit_run_not_cut_in_half() -> None:
    """CCCD 12 số mở đầu `079` trùng prefix di động `07`. Nếu pattern SĐT không neo hai
    đầu dải số, nó sẽ ăn 10 số đầu và chừa lại 2 — PII bị cắt đôi mà vẫn trông như đã lọc."""
    out = redact("cccd 079301234567 nhé")
    assert "[CCCD]" in out.text
    assert "[SĐT]" not in out.text
    assert "[STK]" not in out.text
    assert "67" not in out.text


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("0912345678", "phone"),  # 10 số CÓ prefix di động → SĐT, không phải STK
        ("1234567890", "bank_account"),  # 10 số KHÔNG prefix → STK
        ("123456789", "national_id"),  # 9 số: CMND cũ và STK trùng hình dạng
        ("079301234567", "national_id"),  # 12 số, mở đầu trùng prefix di động
    ],
)
def test_label_priority_is_pinned(raw: str, expected: str) -> None:
    """Ghim hợp đồng ƯU TIÊN NHÃN, không chỉ ghim "có được redact hay không".

    Mọi nhánh đều thay thế, nên đảo thứ tự alternation KHÔNG làm PII rò — nó chỉ dán
    nhầm nhãn, và hậu quả là `hits` (thứ đi vào destination-log) đếm sai loại. Đó là sai
    lệch telemetry chứ không phải rò rỉ, nhưng nó im lặng: không test nào ở trên đỏ nếu
    một dải 9 số đổi từ `national_id` sang `bank_account`. Test này là chỗ nó đỏ.
    """
    assert redact(raw).hits == {expected: 1}


# ---------------------------------------------------------------------------------------
# Biên
# ---------------------------------------------------------------------------------------


def test_empty_string() -> None:
    out = redact("")
    assert out == RedactionResult(text="", hits={})


def test_non_str_input_raises() -> None:
    """Fail-LOUD trên input sai kiểu. Trả về nguyên vẹn sẽ để dữ liệu chưa lọc đi tiếp —
    và lớp bọc B0 fail-closed cần một exception để bắt, không phải một giá trị im lặng."""
    with pytest.raises(TypeError):
        redact(None)  # type: ignore[arg-type]
