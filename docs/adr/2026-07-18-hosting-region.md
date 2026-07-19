# ADR — Hosting Region & Customer-Data Flow (PRE-007)

- **Status:** **ACCEPTED** — Wyatt, 2026-07-19.
- **Decision log:** ✅ Provider = **Together AI** (LLM + embedding), chốt 2026-07-18. ✅ Embedding = **`multilingual-e5-large-instruct`** (1024-dim). ✅ **Deployment-region = Together US serverless ngay** (Open-Q #1, Wyatt 2026-07-19) → self-host VN/SG khi residency buộc. ⚠️ **Legal path (Open-Q #4) KHÔNG đóng bằng chữ ký này** — xem "Nghĩa vụ pháp lý chưa có chủ" ngay dưới.
- **Ghi chú phạm vi chữ ký:** ACCEPTED này chốt **kiến trúc**. Nó KHÔNG xác nhận đã tuân thủ PDPL, và KHÔNG có giá trị tư vấn pháp lý.

> ### ⚠️ Nghĩa vụ pháp lý chưa có chủ (2026-07-19)
>
> Chọn US serverless = **posture Option C**: PII khách VN (tên, sđt, địa chỉ, nội dung đơn) vượt biên sang US. PDPL + Nghị định 356/2025 buộc: **(a)** thoả thuận với bên nhận, **(b)** **TIA nộp Bộ Công an trong 60 ngày kể từ lần chuyển ĐẦU TIÊN** + cập nhật mỗi 6 tháng, **(c)** consent/căn cứ hợp pháp. Chế tài tới **5% doanh thu năm trước hoặc 3 tỷ VND**.
>
> **Hôm nay chưa ai nhận việc này và chưa có deadline.** Ghi ra để nó không trôi thành giả định rằng "ADR ký rồi = xong pháp lý".
>
> **Đồng hồ 60 ngày CHƯA chạy** — GĐ0 mới chỉ có General Chat (seller ↔ AI, không có tin nhắn khách) và corpus wiki chưa land (PRE-003). Nó bắt đầu chạy kể từ **tin nhắn khách hàng THẬT đầu tiên** đi qua embedding/LLM — tức là khi Spec 03c mount webhook Zalo. **Đó là mốc phải có consent-UX + hồ sơ, không phải mốc để bắt đầu nghĩ về nó.**
- **Spec:** `docs/tasks/03-Task-GD0-AcceptanceBackfill.md` PRE-007 (block Phase 1). Gate post-check: `test -f docs/adr/2026-07-18-hosting-region.md && grep -q "<token chấp-thuận>" $_`.
- **Liên quan:** TL-5 trong `docs/tasks/PLAN-TechLead-Decomposition-Roadmap.md` (residency đe doạ F1 embedder đã ship). Spec 05 F1 = `OpenAIEmbedder` / `text-embedding-3-small` (endpoint OpenAI US).

---

## Context

Ohana là copilot cho seller social-commerce **Việt Nam**; khách là người tiêu dùng VN. Tin nhắn khách chứa **personal data**: tên, số điện thoại, địa chỉ giao hàng, nội dung đơn. Pipeline AI hiện tại/kế hoạch đẩy **text tin khách** qua:
1. **Embedding model** — hiện `text-embedding-3-small` (OpenAI, **US**), đã ship ở F1.
2. **LLM drafting** — orchestrator soạn reply (OpenAI/Anthropic, mặc định **US**).
3. **pgvector DB** — lưu embedding + có thể lưu text gốc/chunk.

**Điểm kiến trúc mấu chốt (quyết định cả ADR này):** ràng buộc residency KHÔNG nằm ở chỗ đặt DB, mà ở **data-flow của inference**. Có thể để DB ở VN nhưng nếu embedding/LLM gọi OpenAI-US thì **PII khách vẫn vượt biên**. Vì vậy quyết định thật = *inference đi đâu*, không phải *DB nằm đâu*.

**Legal frame (KHÔNG phải legal advice — luật sư VN + US phải xác nhận).** Verified 2026-07-18 từ advisory công khai:
- **Luật BVDLCN (PDPL) đã hiệu lực 1/1/2026** + **Nghị định 356/2025/NĐ-CP** hướng dẫn — thay/bổ sung khung Nghị định 13/2023.
- **Chuyển ra nước ngoài KHÔNG bị cấm chung**, nhưng buộc: (a) thoả thuận với bên nhận (mục đích / thời hạn / căn cứ pháp lý), (b) **Transfer Impact Assessment (TIA)** nộp Bộ Công an trong **60 ngày** kể từ lần chuyển đầu + cập nhật mỗi 6 tháng, (c) consent / căn cứ hợp pháp.
- **Localization overlay:** ngành thuộc Luật An ninh mạng (**e-commerce / social / payment — Ohana rơi vào**) có thể buộc **lưu dữ liệu user trên server tại VN + pháp nhân đại diện tại VN**. Áp *độc lập* với chuyện inference chạy đâu → **DB / message store nhiều khả năng phải ở VN bất kể chọn LLM nào**.
- **Chế tài:** tới **5% doanh thu năm trước hoặc 3 tỷ VND** (mức cao hơn).

**Hệ quả — KHÔNG có "LLM compliant" theo brand.** Vi phạm hay không do: (1) inference chạy ở đâu, (2) đã có TIA + agreement + consent chưa, (3) localization. Chỉ **self-host open model TRONG VN** mới *tránh hẳn* trigger cross-border; mọi hosted-API (Together-US, Claude, GPT, Bedrock-SG) là "**hợp pháp CHỈ KHI có giấy tờ**".

**Entity note — Ohana là công ty Mỹ vận hành cả VN + US:** tư cách US **KHÔNG miễn** PDPL. Luật áp theo **chủ thể dữ liệu**, không theo nơi đăng ký công ty (hiệu lực ngoài lãnh thổ, kiểu GDPR); và tổ chức *nước ngoài* chính là đối tượng của điều khoản local-rep-office. → kiến trúc đúng = **two-data-plane theo tài phán**:

| Plane | Chủ thể | Luật áp | LLM cho phép |
|---|---|---|---|
| **VN** (seller VN + khách VN) | công dân VN | PDPL + An ninh mạng | DB **tại VN**; inference **self-host VN** (sạch) *hoặc* hosted + TIA/consent |
| **US** (seller US + khách US) | US persons | state law (CCPA/CPRA…) | **tự do** — Together-US / OpenAI / Anthropic, không localization |

⚠️ **Bẫy US-company:** bản năng centralize hết về DB Mỹ = gom data VN sang US = **vừa vượt biên vừa phá localization**. KHÔNG centralize xuyên tài phán.

ADR này chốt **hệ quả kiến trúc**; phần pháp lý là điều kiện song song, không thay bằng ADR.

PRE-007 yêu cầu ADR cover 4 thứ: (a) region, (b) data-flow qua LLM provider, (c) PDPD compliance path, (d) pgvector location + backup region.

---

## Options

| Trục | **A. VN-only** (Viettel/VNG/FPT Cloud) | **B. Singapore** (AWS `ap-southeast-1`) ⭐ | **C. US** (mặc định hiện tại) |
|---|---|---|---|
| DB (pgvector) + backup | VN | Singapore | US |
| LLM inference | ❌ không major provider có VN region → **self-host model** (yếu VN-commerce) *hoặc* vẫn vượt biên | Claude via **Bedrock `ap-southeast-1`** (in-region); OpenAI via **Azure SEA** | OpenAI/Anthropic native US |
| Embedding | Self-host (bge-m3…) hoặc vượt biên | Bedrock Titan / Cohere / **Voyage** in-region | OpenAI US (F1 hiện tại) |
| Vượt biên PII khách | Không (nếu self-host) / Có (nếu gọi US) | **VN→SG** (1 chặng, jurisdiction DP mạnh — PDPA) | **VN→US** (xa nhất) |
| Latency VN→region | Thấp nhất (nội địa) | ~30–50ms (tốt) | ~200ms+ (LLM token-gen vẫn chi phối p95, nhưng RTT cộng dồn ở embedding/retrieval) |
| PDPD compliance surface | Nhỏ nhất (không vượt biên) **nhưng** đánh đổi chất lượng model | Trung bình — vẫn cần hồ sơ VN→SG, nhưng SG là hub DP chuẩn | Lớn nhất — hồ sơ + consent + xa |
| Tác động F1 (đã ship) | Phải đổi embedder → re-embed | **Phải đổi embedder off OpenAI-US → re-embed + re-verify ISSUE-016** | **Không đổi** (F1 giữ nguyên) |
| Eng cost ngay | Cao (self-host infra + model ops) | Trung bình (đổi provider SDK + re-embed) | Thấp nhất |
| Rủi ro dài hạn | Model quality trần thấp cho VN nuance | Thấp | Compliance + latency nợ về sau |

---

## Decision — provider = Together AI (Wyatt directive 2026-07-18); deployment-region còn mở

**Provider (chốt 2026-07-18):** **Together AI — open-weight inference, CẢ LLM lẫn embedding.** LLM drafting = open model host bởi Together (Llama / Qwen / DeepSeek… — eval-SEED chọn, Open-Q #3); **embedding = `intfloat/multilingual-e5-large-instruct` (1024-dim) — Wyatt chốt chuyển khỏi OpenAI**. → F1 OpenAI-US dependency được xoá (chi tiết Consequences).

**Điểm mấu chốt — Together TÁCH trục provider khỏi trục region.** Vì model là **open-weight**, cùng một model chạy được: Together **US serverless** (rẻ, nhanh, ngay) *hoặc* self-host VN/SG *hoặc* Together Dedicated APAC — **không phải re-do prompt/eval** (weights giống hệt). API độc quyền (OpenAI/Anthropic) KHÔNG cho điều này — khoá cứng vào region + weights của họ. → Together biến residency từ bài toán *đổi model* thành bài toán *đổi nơi deploy*. Đây là giá trị chiến lược thật.

⚠️ **Nhưng Together KHÔNG tự giải residency — đừng nhầm.** Verified 2026-07-18: DC Together = **US primary + Europe**; APAC = "options based on scale" (dedicated/enterprise, **KHÔNG có standard SG serverless region**). → dùng Together **serverless ngay = vẫn posture Option C (vượt biên VN→US)**, cần consent + hồ sơ như C. Together mua được **exit-option rẻ**, không phải compliance miễn phí.

**Kết luận (2 trục):**
- **Provider (chốt):** Together open-weight. Buộc `embedder` + `model_router` land **provider + deployment agnostic** (khớp §1.1.5 land-early) — không hardcode endpoint/region.
- **Deployment-region (Wyatt chốt tiếp, Open-Q #1):**
  - *Now (GĐ0 pilot):* Together **US serverless** — posture Option C (consent + dossier, legal ký). Rẻ/nhanh để wedge.
  - *Later (khi residency buộc):* self-host VN/SG **hoặc** Together Dedicated APAC (verify scale + cost) — same weights, chỉ re-embed nếu đổi embedding model.
- **Model-quality gate:** open model (e5 / Qwen / Llama) đủ tốt cho tiếng Việt hay không → **eval-SEED (Spec 03d-D3) là cổng quyết**, KHÔNG assume. Nếu open model rớt eval → reconsider provider trước khi pilot.

*(Options table trên giờ đọc là trục **deployment-region**; với Together open-weight, ô "tác động F1 = phải đổi model" hạ xuống "đổi nơi deploy" vì weights portable.)*

---

## Consequences (điều decision này ép xuống downstream)

**F1 / ISSUE-016 làm lại (embedding → Together):**
- Thay `OpenAIEmbedder` (`text-embedding-3-small`, **1536-dim**) → `TogetherEmbedder` (`intfloat/multilingual-e5-large-instruct`, **1024-dim, 93 ngôn ngữ incl tiếng Việt**).
- Hệ quả cứng: (a) **đổi dimension pgvector 1536→1024** → Alembic migration cột `embeddings.vector` + **re-embed toàn corpus** khi PRE-003 land; (b) `app/config.py` thêm provider Together + `default_embedder()` chọn Together; (c) ISSUE-016 live acceptance chạy trên e5, KHÔNG phải OpenAI.
- **Lợi kèm:** e5 multilingual xử tiếng Việt **tốt hơn** embedding English-centric của OpenAI → đây là *nâng cấp chất lượng*, không chỉ compliance. → Spec 05 status: F1 embedder-provider **chưa final** cho tới khi ADR này được Wyatt duyệt.

**LLM drafting:**
- `orchestrator` + `model_router` (Spec 03d-D4) target Together endpoint, provider-agnostic; chọn open model VN-capable (Qwen/Llama/DeepSeek/SeaLLM — eval-SEED quyết, Open-Q #3). Không hardcode model id (nợ demo `claude-sonnet-4-6` §8.2 xoá luôn).
- ⚠️ Availability/model list đổi theo thời gian — verify trên Together thực tế, đừng tin ADR như bảng giá.

**Deployment-region (theo Open-Q #1):**
- *US serverless now:* consent + hồ sơ vượt biên VN→US (như posture C) — legal ký. Consent-UX land onboarding GĐ0 (shops table, Spec 03b-B1). DB/backup: cân nhắc để pgvector ở VN/SG dù inference US (giảm bề mặt data-at-rest).
- *VN/SG later:* self-host open model hoặc Together Dedicated — same weights, re-embed chỉ khi đổi embedding model.

**Chung:**
- `model_router` + embedder factory **provider + deployment agnostic** (không hardcode) — abstraction land-early bất kể region (§1.1.5).
- **Data minimization:** chỉ gửi text cần cho inference, tách PII thừa (sđt/địa chỉ) khỏi prompt nếu không cần — giảm bề mặt bất kể deploy đâu.

---

## Open questions — Wyatt chốt khi duyệt

1. ~~**Deployment-region**~~ ✅ **RESOLVED 2026-07-19 — Wyatt chốt: Together US serverless ngay**, posture C (consent + dossier), self-host VN/SG khi residency buộc. Lý do: đây đã là thực tế đang chạy (spec 07 G0–G2 dùng Together US serverless), nên chữ ký phê chuẩn hiện trạng thay vì mô tả một hệ thống không tồn tại. Weights open nên đổi nơi deploy sau KHÔNG phải làm lại prompt/eval — chỉ re-embed nếu đổi embedding model.
2. ~~Embedding có đi cùng Together không?~~ ✅ **RESOLVED 2026-07-18** — Wyatt chốt chuyển embedding → Together `multilingual-e5-large-instruct` (1024-dim). F1 swap thành work-item (xem Consequences).
3. **LLM model nào trên Together** cho drafting VN — Qwen2.5 / Llama-3.x / DeepSeek / SeaLLM? (eval-SEED chọn, không chốt vội).
4. **Legal:** đường hồ sơ vượt biên VN→US + phiên bản luật áp dụng — **VẪN MỞ, CHƯA CÓ CHỦ** (Wyatt 2026-07-19: ghi là điều kiện song song, chưa giao ai). Chữ ký ACCEPTED ở trên KHÔNG đóng mục này. Cần luật sư VN + US xác nhận; deadline thực tế = trước khi tin nhắn khách THẬT đầu tiên chạy qua pipeline (Spec 03c mount webhook). Xem hộp cảnh báo đầu file.
5. **Consent-UX:** land onboarding GĐ0 (shops table, Spec 03b-B1) — thêm scope?
6. **Budget re-embed** (1536→1024) khi PRE-003 land — chấp nhận?

---

## How to accept

~~Wyatt duyệt bằng cách…~~ ✅ **ĐÃ KÝ — Wyatt, 2026-07-19.** Status ở đầu file đã mang token chấp-thuận, gate PRE-007 của Spec 03 Phase 1 giờ XANH.

**Việc bật ra ngay sau chữ ký (chưa làm — đừng coi ADR này là đã thực thi):**

1. **F1 embedder swap** — `OpenAIEmbedder` (`text-embedding-3-small`, 1536) → Together `multilingual-e5-large-instruct` (1024). Kéo theo: Alembic migration đổi `Vector(1536)` → `Vector(1024)` (`db/models.py:_EMBED_DIM`), re-embed toàn corpus khi PRE-003 land, và **ISSUE-016 live acceptance phải chạy lại trên e5 — kết quả cũ trên OpenAI KHÔNG áp dụng**.
2. **Spec 05 status** — F1 embedder-provider ghi là "chưa final chờ ADR"; giờ đã final, cập nhật lại.
3. **Consent-UX** (Open-Q #5) — land ở onboarding cùng shops table (Spec 03b-B1), TRƯỚC khi webhook mount.
4. **Legal (Open-Q #4)** — chưa có chủ. Xem hộp cảnh báo đầu file.

⚠️ Không mục nào ở trên nằm trong spec 07. Chúng là công việc mới, cần spec/phase riêng.
