# DEC-OHANA-04 — Waiver: chấp nhận EVIDENCE của 22 phase DONE trước khi CI xanh lần đầu

- **Date:** 2026-07-20
- **Status:** ACCEPTED
- **Signed-by:** Wyatt · 2026-07-20
- **Context:** ISSUE-019. Sau khi GitHub Actions hồi phục sau outage, hỏi thẳng API thay vì suy luận local.

---

## Sự thật đo được

```
23 run  = TOÀN BỘ lịch sử CI của repo (cũ nhất 2026-07-17T15:53, b93b8ed)
✅  4 xanh — CẢ BỐN sau commit vá ruff 01c2479 (2026-07-19T15:36)
❌ 19 đỏ
```

**CI chưa từng xanh một lần nào** cho tới `01c2479`. Spec 04 / 05 / 06 / 07 — mọi phase — được `adp-checkpoint.sh` stamp DONE trong lúc CI đỏ.

**Và phạm vi hỏng rộng hơn "lint đỏ".** Lấy mẫu run `29671576305` (spec 07 G2 checkpoint evidence):

```
✅  6. Headless guardrail          success
❌  7. Ruff lint (incl S/bandit)   failure
⏭️   8. Ruff format check           skipped
⏭️   9. Mypy (strict)               skipped
⏭️  10. DB migrate                  skipped
⏭️  11. Pytest                      skipped     ← test CHƯA TỪNG CHẠY TRÊN CI
```

Ruff chết ở step 7 ⇒ mọi step sau bị skip. Nghĩa là suốt 19 run đỏ, **CI chưa từng chạy test suite, chưa từng chạy migration trên Postgres sạch của runner**. Toàn bộ bằng chứng test giai đoạn đó là local-only.

Nguyên nhân gốc (ISSUE-019): `.ruff_cache` do bản ruff cũ ghi không bị vô hiệu khi ruff nâng cấp ⇒ `ruff check .` local trả xanh trong khi cùng source trên CI trả đỏ. `GATE_FULL` của ADP nuốt cái xanh giả đó vào EVIDENCE.

⚠️ **Chưa verify:** rule cụ thể của các run đỏ CŨ. S603 chỉ land cùng spec 07 (19/07), nên đỏ từ 17–18/07 do rule khác. Log không lấy được (Actions còn partial-outage). Mới chứng minh **cùng một step**, chưa phải **cùng một nguyên nhân**.

## Options considered

1. **Re-stamp toàn bộ 22 EVIDENCE cũ** — checkout từng commit checkpoint, chạy lại GATE_FULL dưới toolchain đã pin, stamp lại.
   - *Pros:* mỗi phase DONE lấy lại nghĩa gốc "đã qua gate thật tại thời điểm ký".
   - *Cons:* 22 lần checkout + cài deps + chạy full gate. Và **kết quả gần như chắc chắn ĐỎ** — chính vì thế mới có ISSUE-019. Re-stamp sẽ biến 22 phase DONE thành FAILED, tức phải mở lại spec đã đóng, trong khi code hiện tại đã xanh. Đắt, và đo một câu hỏi lịch sử không ai còn cần trả lời.

2. **Chấp nhận + ghi waiver** ← **CHỌN**
   - *Pros:* HEAD đã qua **đủ 11 step** trên container sạch (xem dưới). Thứ thật sự quan trọng — "code hôm nay có đúng không" — đã được chứng minh bằng CI thật. Waiver ghi rõ cái gì mất, để không ai đọc "DONE" rộng hơn nó đáng.
   - *Cons:* mất vĩnh viễn khả năng nói "phase X đã qua gate thật tại thời điểm ký". Con số `adp-status.sh` cho giai đoạn đó yếu hơn vẻ ngoài của nó.

3. **Re-stamp chọn lọc** (chỉ phase chạm RISK_PATHS) — bỏ, vì cùng chi phí nhận thức mà lại đẻ ra hai hạng EVIDENCE khác nhau, khó giải thích hơn cả hai phương án trên.

## Quyết định

**Giữ nguyên 22 EVIDENCE cũ, KHÔNG re-stamp.** Waiver này là bản ghi công khai về điều đó.

### Cơ sở: HEAD đã qua CI thật, đủ 11 step

Run `29709797545` (`aae835c`) — container sạch của runner, không phải máy Wyatt:

```
✅ guardrail · ✅ ruff lint · ✅ ruff format · ✅ mypy strict
✅ alembic upgrade (Postgres pgvector:pg16 thật) · ✅ pytest
```

Đây là lý do waiver đứng vững: câu hỏi "code hiện tại có đúng không" **đã có câu trả lời từ CI**, không cần khảo cổ.

### Waive cái gì — nói chính xác

| | |
|---|---|
| **ĐƯỢC waive** | Yêu cầu EVIDENCE của 22 phase DONE trước `01c2479` phải tái lập được. Chúng ghi lại một gate local mà CI mâu thuẫn. |
| **KHÔNG waive** | Tính đúng của code hiện tại — HEAD qua đủ 11 step CI. |
| **KHÔNG waive** | Quy tắc từ nay: `--no-cache` + toolchain pin. Vi phạm mới KHÔNG được viện waiver này. |
| **KHÔNG waive** | Nghĩa vụ nói thật. "DONE" cho phase trước `01c2479` nghĩa là **"gate local pass, CI chưa từng xác nhận"** — không phải "đã qua gate thật". Ai trích số liệu giai đoạn đó phải kèm câu này. |

## Consequences

- `adp-status.sh` hiện báo 24/34 phase. **22 trong số đó mang EVIDENCE yếu** theo nghĩa trên. Chỉ spec 08 (E0/E1/E2) là được ký trong thời kỳ CI xanh.
- Không mở lại spec 04/05/06/07. Chúng đóng, kèm chú thích này.
- Nếu sau này một bug truy về giai đoạn đó, **đừng ngạc nhiên và đừng coi là bí ẩn** — EVIDENCE của nó chưa bao giờ chứng minh điều người ta tưởng.
- Waiver này áp cho **đúng 22 phase trước `01c2479`**. Không phải giấy phép chung, không nới cho phase tương lai.

## Còn treo (không thuộc waiver)

- Rule thật của các run đỏ 17–18/07 — chưa đào được log.
- ISSUE-019 action 6: runtime deps chưa pin (`openai>=1.30` đang chạy 2.45).
