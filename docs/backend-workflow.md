# Ohana AI — Workflow Backend

Mô tả luồng chạy phía backend của hai persona. Mức trừu tượng: **thành phần và dòng dữ liệu**, không đi vào code.

---

## 0. Hai persona, hai luồng, một tầng hạ tầng

Hệ thống có **hai luồng độc lập**, không dùng chung đường chạy:

| | **Ohana AI** | **AI Seller** |
|---|---|---|
| Ai gọi | User đang dùng app Ohana | Khách hàng nhắn shop qua Zalo/FB/IG |
| Xưng danh | "Ohana AI" | **Là shop** — không lộ Ohana |
| Trả lời về | Tính năng, gói cước, cách dùng app Ohana | Sản phẩm, giá, tồn kho, chính sách của shop |
| Cần `shop_id`? | **Không** — kiến thức là của nền tảng, dùng chung | **Có** — mọi thứ scope theo shop |
| Nguồn kiến thức | RAG trên corpus nền tảng | Tool + trường dữ liệu của shop, **không RAG** |
| Vào/ra | Đồng bộ, user chờ ngay | Bất đồng bộ, có bước người duyệt |
| SLA | ≤ 3s p95 | ACK ≤ 2s, soạn nháp ≤ 30s |
| Auto-gửi | N/A | **Không** — 100% seller duyệt tay |

Cả hai **dùng chung tầng hạ tầng** — LLM client, embedder, retriever, tool registry, channel adapter — nhưng đó là quan hệ *cùng import một thư viện*, **không phải** cùng đi một đường chạy. §5 ràng buộc thêm: hai luồng chạy trên **hai service khác nhau**, không share process.

---

## 1. Luồng A — Ohana AI

Hỏi–đáp đồng bộ. User hỏi, trả lời ngay, không ai duyệt.

```
User (SPA)
  │
  ▼
POST /api/chat
  │
  ├─ Xác thực: session cookie → danh tính (user_id, role)
  │
  ├─ Nhúng câu hỏi thành vector
  │
  ├─ Tra corpus nền tảng
  │     • một corpus duy nhất, dùng chung mọi user
  │     • không lọc theo shop — kiến thức này không thuộc shop nào
  │
  ├─ Ráp prompt:  persona Ohana AI  +  đoạn corpus lấy được  +  câu hỏi
  │
  ├─ Gọi LLM
  │
  ▼
Trả về: text  +  nguồn trích  +  cờ đã-có-căn-cứ-hay-chưa
```

**Quy tắc quan trọng:** không tra được đoạn nào thì **nói không biết**, không trả lời chay. Đây là persona duy nhất được phép xưng "Ohana AI", nên nó cũng là persona dễ bịa nhất về Ohana — chặn ở đúng chỗ này.

Luồng này **không chạm dữ liệu shop**. Không đọc, không ghi.

---

## 2. Luồng B — AI Seller

Bất đồng bộ, có cổng duyệt. Ba nhịp rời nhau.

### 2.1 Nhịp 0 — Webhook nhận & ACK

Đây là biên giới duy nhất giữa nền tảng ngoài và hệ thống. Sai ở đây là mất tin, sai gấp đôi là gửi trùng.

```
Zalo / FB / IG gửi webhook
  │
  ▼
Webhook endpoint
  │
  ├─ Verify chữ ký trên body GỐC (byte nguyên, chưa parse)
  │
  ├─ Suy shop_id:
  │     shop_id = f(endpoint, page_id trong body sau khi verify)
  │     ⚠️ 1 endpoint có thể phục vụ nhiều page — không giả định 1-1
  │     ⚠️ page_id chỉ dùng SAU khi signature đã pass
  │
  ├─ Idempotency check
  │     key = (channel, platform_msg_id)
  │     đã thấy → trả 200, KHÔNG enqueue lại
  │
  ├─ Enqueue: {shop_id, raw_event, received_at}
  │
  ▼
Return 200 trong ≤ 2s
```

**Ba ràng buộc cứng:**
1. **ACK trước, xử lý sau.** LLM có thể mất 5–15s; webhook timeout 5s. Xử lý inline là bảo đảm gửi trùng.
2. **Idempotent tại DB.** Unique constraint trên `(channel, platform_msg_id)`. Không dựa vào cache.
3. **Không bao giờ tin body trước khi verify.** `shop_id`, `page_id`, `sender_id` — tất cả là dữ liệu thù địch cho tới khi chữ ký pass.

### 2.2 Nhịp 0.5 — Coalescing

Khách thường nhắn xé nhỏ: `"hi"` → `"áo A còn ko"` → `"size M nha"`. Xử lý từng tin sinh ba nháp, mỗi nháp thiếu ngữ cảnh của tin sau.

```
Worker nhận event từ queue
  │
  ├─ Ghi tin vào conversation
  │
  ├─ Đặt/refresh debounce timer cho conversation này
  │     debounce = 4 giây (hằng số, không cấu hình per-shop)
  │
  ▼
Khi timer nổ → chuyển sang nhịp 1
```

Debounce cho **cả conversation**, không cho từng tin. Tin mới đến trong window → reset timer, không sinh nháp mới.

### 2.3 Nhịp 1 — soạn nháp

```
Trigger từ nhịp 0.5
  │
  ├─ Lấy 6 lượt gần nhất của conversation
  │     (cứng; không summary, không structured memory)
  │
  ├─ Phân loại ý định (rules)                (§2.4)
  │
  ├─ Lấy dữ kiện theo tầng tương ứng           (§3)
  │     Snapshot mọi giá trị tầng 1 tại T0
  │     Ghi lại: nguồn, giá trị, thời điểm
  │
  ├─ Ráp prompt: persona + 6 lượt + dữ kiện + tin mới
  │
  ├─ Gọi LLM
  │
  ▼
Nháp: nội dung  +  ý định  +  snapshot tầng 1
  │
  ▼
Cổng chính sách                              (§2.4)
```

**Snapshot là bắt buộc.** Draft chờ duyệt 30 phút, tồn kho có thể đã đổi. Snapshot cho phép §2.5 phát hiện drift lúc duyệt.

### 2.4 Cổng chính sách

Đầu vào: `(ý định từ rules, cấu hình shop)`. Đầu ra: `GIỮ | GIỮ + ESCALATE`.

**Không có nhánh GỬI.** Mọi nháp đều phải seller duyệt tay. Đây là quyết định thiết kế, không phải giới hạn kỹ thuật — nguyên tắc *AI gợi ý, người quyết* áp cho từng câu trả lời.

**Ý định lấy từ đâu:**
- ✅ **Rules layer** (keyword/regex trên tin khách + intent taxonomy 15 loại).
- ❌ Không hỏi LLM self-report confidence — LLM chấm cao ngay cả khi bịa.
- ❌ Không có classifier riêng — chưa đủ label data để train đàng hoàng.

```
Cổng chính sách
  │
  ├─ Rule match ý định nhạy cảm
  │     • khiếu nại / hoàn tiền / dọa kiện
  │     • "bạn có phải bot không" / yêu cầu gặp người thật
  │     • đề cập luật, cơ quan chức năng
  │       → GIỮ + ESCALATE (notify riêng: push/badge urgent)
  │
  ├─ Ngoài messaging window platform
  │       → GIỮ + đánh dấu window đã đóng
  │
  ├─ Shop chạm cost cap ngày
  │       → GIỮ, không gọi LLM cho tin tiếp theo trong ngày
  │
  └─ Mọi trường hợp còn lại
          → GIỮ (mặc định)
```

**ESCALATE ≠ GIỮ thường.** ESCALATE bắn notification riêng (push, badge urgent, có thể SMS tuỳ shop cấu hình). GIỮ thường chỉ nằm im trong inbox chờ seller mở.

### 2.5 Nhịp 2 — seller vào duyệt

```
Seller mở hộp thư
  │
  ▼
GET /api/inbox
  │
  ├─ Chỉ nháp của shop mình
  ├─ Sắp xếp: ESCALATE > sắp hết window > mới nhất
  ├─ Mỗi nháp hiển thị: TTL còn lại, snapshot tại T0
  │
  ├─ Duyệt →
  │     ├─ Re-fetch tầng 1 tại T1
  │     ├─ So sánh với snapshot T0
  │     ├─ Lệch quá ngưỡng (ví dụ giá đổi, hết hàng)
  │     │     → cảnh báo seller trước khi gửi
  │     ├─ Gửi qua adapter kênh
  │     └─ Ghi label = "approved"                    (nuôi §8)
  │
  ├─ Từ chối / sửa →
  │     └─ Ghi label = "rejected" hoặc "edited"      (nuôi §8)
  │
  └─ Hết TTL → auto-close, log lý do, thông báo seller
```

TTL của mỗi nháp = `min(messaging window của platform, ngưỡng cấu hình shop)`. Zalo/FB có window riêng; vượt window là gửi fail hoặc bị tính phí.

**Ghi label mỗi lần duyệt/từ chối/sửa** — chi phí gần như 0 nhưng là điều kiện tiên quyết cho §8. Không ghi từ đầu = phase sau phải chờ tích data lại từ đầu.

---

## 3. Ba tầng dữ liệu của AI Seller

Phân tầng theo **hình dạng dữ liệu**, không theo loại câu hỏi. Đây là điểm kiến trúc cốt lõi.

```
        Câu hỏi của khách
               │
      ┌────────┼────────────────┬─────────────────────┐
      ▼        ▼                ▼                     ▼
   TẦNG 1   TẦNG 2          TẦNG 3              (ngoài phạm vi)
```

**Tầng 1 — Dữ kiện động.** Thay đổi theo thời gian, nguồn nằm ngoài.
→ Gọi API lấy giá trị thật tại thời điểm hỏi. **Snapshot bắt buộc** (§2.3).
*Còn hàng không, giá bao nhiêu, đơn tới đâu rồi.*

**Tầng 2 — Dữ kiện tĩnh có cấu trúc.** Là một phép ánh xạ: đưa tham số vào, ra giá trị.
→ Lưu dạng dữ liệu có cấu trúc trên hồ sơ shop, tra bằng **hàm tất định**.
*Cao 1m6 nặng 50kg mặc size gì; giao về Cà Mau mất mấy ngày.*

**Tầng 3 — Văn xuôi và tông giọng.** Không tham số hoá được.
→ Trường văn bản trên hồ sơ shop, ráp thẳng vào prompt.
*Chính sách đổi trả, cách chào, kiểu nói chuyện của shop.*

### Vì sao tầng 2 không dùng RAG

Ba lý do, đều là lý do an toàn chứ không phải tối ưu:

1. **Cắt đoạn phá bảng.** Corpus bị cắt theo độ dài; bảng size sẽ đứt giữa chừng, đoạn lấy về có thể mất cột.
2. **Đo độ giống trên số là vô nghĩa.** "1m6 50kg" và một bảng số không có quan hệ ngữ nghĩa nào đáng tin.
3. **RAG không bao giờ nói "không biết".** Nó luôn trả về mấy đoạn gần nhất, kể cả khi chẳng đoạn nào liên quan. Hàm tra cứu thì trả **không tìm thấy** một cách dứt khoát — và chính tín hiệu đó là thứ nuôi cổng chính sách. Dùng RAG ở đây là bịt mất giác quan của cổng.

Hàm tất định **kiểm thử được bằng khẳng định thật** — đưa vào 1m6/50kg phải ra đúng size M. Không cần chấm điểm bằng LLM, không cần bộ mẫu vàng.

**Do đó: AI Seller không có kho vector nào.** Ngoại lệ đã biết và đã xếp lịch riêng: tìm sản phẩm theo mô tả ("áo cổ tim tôn dáng") là bài ngữ nghĩa thật — nhưng đó là giai đoạn sau (§8.4).

---

## 4. Hồ sơ shop và cổng duyệt persona

```
Hồ sơ shop
  ├─ Phần persona   (văn bản, có version)     → VÀO prompt mỗi lượt
  │    tên hiển thị, ngành hàng, ghi chú tông giọng,
  │    chính sách đổi trả / COD / giao hàng, câu chào
  │    ⚠️ Trần token cứng, enforce LÚC SAVE (không phải lúc build prompt)
  │    ⚠️ Cache theo (shop_id, version); invalidate khi save
  │
  ├─ Phần tri thức  (có cấu trúc)             → KHÔNG vào prompt
  │    bảng size, bảng thời gian giao theo vùng
  │    → chỉ hàm tra cứu đọc, và chỉ kết quả tra ra mới vào prompt
  │
  ├─ Trạng thái duyệt persona
  │    nháp | đã duyệt  +  ai duyệt  +  duyệt lúc nào
  │
  └─ Cấu hình vận hành
       cost cap token/ngày, kênh notify escalate,
       ngưỡng lệch tầng 1 cần cảnh báo lúc duyệt
```

**Cổng duyệt persona bắt buộc.** Persona chưa duyệt → AI Seller chạy persona mặc định, không dùng hồ sơ đó. Nguyên tắc *AI gợi ý, người quyết* áp cho **cả persona**, không chỉ cho từng câu trả lời. Một persona sai làm hỏng mọi câu sau nó, nên cần cổng chặt hơn chứ không lỏng hơn.

**Trần token enforce lúc save** — không phải lúc build prompt. Truncate lúc build có thể cắt giữa câu "chính sách đổi trả" → AI hiểu sai chính sách. Ở tầng save, seller thấy được giới hạn và tự viết lại.

---

## 5. Ranh giới bắt buộc

Ràng buộc an toàn, không phải sở thích thiết kế.

- **Luồng A và B chạy trên hai service riêng**, không share process. Crash một bên không kéo bên kia. Bịa của A không có đường vật lý nào tới khách của B.
- **Không gộp thành một bộ điều phối có nhánh rẽ theo persona.** Một câu lệnh rẽ nhánh là đủ để phá ranh giới trên.
- **`shop_id` luôn đến từ danh tính đã xác thực hoặc suy ra từ endpoint** — không bao giờ từ thân yêu cầu chưa verify.
- **Mọi truy vấn dữ liệu shop lọc theo shop ngay ở tầng cơ sở dữ liệu**, không lọc sau khi lấy về.
- **Cost cap cứng theo shop.** Hard limit token/ngày. Vượt → cổng chính sách chuyển tất cả sang GIỮ, không gọi LLM tiếp trong ngày. Bảo vệ khỏi shop bị spam bot hoặc cấu hình sai.
- **Dữ liệu xuyên biên giới.** Nội dung tin khách gửi tới LLM foreign nằm trong phạm vi Nghị định 13/2023 + luật 2026. Ràng buộc: (a) filter PII trước khi gửi lên LLM, (b) DPIA riêng cho từng nhà cung cấp LLM, (c) log destination cho audit. Không quyết ở tầng dưới.

---

## 6. Trạng thái hiện tại so với mục tiêu

| Mắt xích | Hiện tại | Khoá tuần đầu prod |
|---|---|---|
| Luồng A — endpoint chat | ✅ chạy thật | |
| Luồng A — nối corpus nền tảng | ❌ | |
| Luồng A — persona có tên | ❌ | |
| Luồng B — webhook ACK + idempotency | ❌ **chưa có** | ✅ |
| Luồng B — queue + worker | ❌ **chưa có** | ✅ |
| Luồng B — coalescing debounce 4s | ❌ | |
| Luồng B — rules layer intent nhạy cảm | ❌ **chưa có** | ✅ |
| Luồng B — bộ soạn nháp (last-N=6) | ❌ | |
| Luồng B — cổng chính sách | ✅ khung | thiếu ESCALATE, cost cap, window |
| Luồng B — hộp thư duyệt | ✅ mở, chưa có nháp | thiếu TTL, snapshot diff, sort ESCALATE, ghi label |
| Hồ sơ shop | ❌ **chưa có bảng nào** | ✅ |
| Hai hàm tra cứu tầng 2 | ❌ | |
| Cost cap per shop | ❌ | ✅ |
| PII filter + DPIA cross-border | ❌ | ✅ |

**Tóm lại:** khoá tuần đầu prod = **webhook ACK/idempotency, rules layer, cost cap, PII filter**. Bốn thứ này định hình schema và ràng buộc của mọi thứ đến sau.

---

## 7. Thứ tự triển khai
<!-- anchor:w-7.1-webhook -->
### 7.1 Webhook + queue + idempotency
...

<!-- anchor:w-7.2-rules-intent -->
### 7.2 Rules layer intent nhạy cảm
...

<!-- anchor:w-7.3-draftschema -->
### 7.3 Draft schema TTL + snapshot + label
...

<!-- anchor:w-7.4-shop-profile -->
### 7.4 Hồ sơ shop
...

<!-- anchor:w-7.5-draft-pipeline -->
### 7.5 Bộ soạn nháp
...

<!-- anchor:w-7.6-pii-dpia -->
### 7.6 PII filter + DPIA
...

<!-- anchor:w-7.7-corpus-luong-a -->
### 7.7 Corpus Ohana AI (Luồng A)
...

Có phụ thuộc kiến trúc, không đảo được:

1. **Webhook + queue + idempotency** (§2.1). Không có nền này, mọi thứ sau đều gửi trùng.
2. **Rules layer intent nhạy cảm** (§2.4). Danh sách keyword/regex cho 4–5 nhóm intent nhạy cảm. Chốt được trong 1 ngày.
3. **Draft schema với TTL + snapshot + label field** (§2.3, §2.5). Sai schema từ đầu là refactor lớn. Có `label` field từ ngày một để nuôi §8.
4. **Hồ sơ shop** (§4). Có schema mới nạp được persona + tri thức tầng 2.
5. **Bộ soạn nháp** (§2.3). Ghép 1–4 thành một pipeline chạy được.
6. **PII filter + DPIA cross-border** (§5). Phải xong trước khi ra khỏi môi trường sandbox.
7. **Nối corpus nền tảng vào luồng A** (§1). Độc lập với B, có thể chạy song song từ bước 1.

Bước 1–3 là khoá — làm sai thì bước 4–7 phải làm lại.

---

## 8. Đường tiến hoá

Mỗi quyết định đơn giản ở các mục trên được chọn vì nâng cấp được **mà không phá kiến trúc**. Ghi rõ ở đây để phase sau không đi vòng.

### 8.1 Rules → Rules + Classifier (bật auto-gửi)

**Trigger nâng cấp:** khi có ≥ 5.000 draft đã duyệt/từ chối/sửa (khoảng vài shop chạy 4–8 tuần).

**Nâng cấp gì:**
- Train small classifier trên `(tin khách, ý định, label)` từ inbox log.
- Thêm classifier score vào output của bộ phân loại intent.
- Cổng chính sách thêm 1 nhánh: `confidence ≥ ngưỡng + shop cho phép auto-gửi cho intent này` → GỬI.

**Không phá gì:**
- Rules layer giữ nguyên — vẫn là nhánh nhạy cảm mặc định GIỮ.
- Cổng chính sách chỉ **thêm** nhánh GỬI, không sửa nhánh cũ.
- Không đổi schema draft, không đổi schema conversation.

### 8.2 Last-N=6 → Last-N + Summary

**Trigger nâng cấp:** khi phân bố độ dài hội thoại có p75 > 6 lượt, hoặc có repeat customer thường xuyên (mỹ phẩm, phụ kiện).

**Nâng cấp gì:**
- Thêm 1 field `conversation_summary` vào bảng conversation.
- Regenerate summary khi vượt trần lượt (không phải mỗi lượt).
- Prompt = persona + summary + 6 lượt gần + tin mới.

**Không phá gì:**
- Bảng conversation chỉ thêm field, không đổi field cũ.
- Pipeline soạn nháp thêm 1 bước trước ráp prompt, không đổi thứ tự.
- Summary rỗng (hội thoại ngắn) → hành vi giống hiện tại.

### 8.3 Debounce cứng → Debounce có override

**Trigger nâng cấp:** khi log `khoảng thời gian giữa 2 tin liên tiếp của cùng khách` có phân bố lệch rõ theo loại shop (ăn uống p50 < 2s, tư vấn p50 > 6s).

**Nâng cấp gì:**
- Thêm 1 field `debounce_ms` vào cấu hình vận hành, default 4000.
- Cho seller override thành 2000 hoặc 6000.

**Không phá gì:**
- Timer logic không đổi — chỉ đọc hằng số từ config thay vì hard-code.
- Shop không override → hành vi giống hiện tại.

### 8.4 Không có kho vector → Semantic search cho catalog

**Trigger nâng cấp:** khi shop có catalog > vài trăm SP và intent "tìm sản phẩm theo mô tả" xuất hiện thường xuyên trong inbox.

**Nâng cấp gì:**
- Thêm vector index **chỉ trên catalog SP** (không phải trên tầng 2 tổng quát).
- Thêm 1 tool riêng: `search_products_by_description(shop_id, query) → [product_id]`.
- Tool này gọi vector search + rerank; kết quả vào prompt như tầng 1.

**Không phá gì:**
- Tầng 2 (bảng size, bảng giao hàng) vẫn dùng hàm tất định.
- Không có vector index nào chạm tầng 2.
- Là **thêm** tool, không thay đổi cơ chế tra cứu hiện tại.

---

Bốn đường tiến hoá này là lý do các mục trên chọn được phương án đơn giản mà không hối tiếc: mỗi nâng cấp đều **thêm**, không **thay**.
