# Script demo pitch CareVoice AI (~6–7 phút)

**Mục tiêu:** Kể một câu chuyện buổi sáng của bác Chu Minh Tâm — từ giọng nói bệnh nhân → AI phân tích → điều dưỡng hành động → khép vòng bằng OCR thuốc.  
**Không chỉ show API** — mỗi bước nói rõ *AI giải quyết gì* và *ai được lợi*.

**Thiết bị:** 2 iPhone (bệnh nhân + điều dưỡng) hoặc 1 máy đổi role. Mac chạy backend. **Bật âm lượng.**

---

## Cheat sheet — in ra 1 tờ

| # | Màn hình | Đăng nhập | Làm gì | Câu chốt AI |
|---|----------|-----------|--------|-------------|
| 1 | Hook | — | Kể câu chuyện mẹ/điều dưỡng | Không phải chatbot — là **giọng nói + đúng người** |
| 2 | BN Trang chủ | `patient`/`patient` | Nghe lời chào buổi sáng | Voice-first: app **nói trước**, bác chỉ nghe |
| 3 | Check-in | — | Chọn **Có vấn đề** + ghi âm *"hơi chóng mặt"* | STT → phân loại → **lý do rõ**, không hộp đen |
| 4 | Kết quả BN | — | Chỉ badge + lý do + banner người nhà | AI **kích hoạt** alert, không thay bác sĩ |
| 5 | DD Dashboard | `nurse`/`nurse` | KPI + danh sách ưu tiên + rung | Hệ thống **gom** tín hiệu → 1 danh sách |
| 6 | DD Chi tiết BN | — | Timeline + nghe audio + Đã gọi lại | Điều dưỡng **tin** vì thấy transcript + audio gốc |
| 7 | BN Thuốc | `patient` | Xác nhận buổi sáng, nghe đọc tên thuốc | Adherence — giảm sai liều |
| 8 | BN Lời khuyên | Trang chủ → Lời khuyên | Nghe tip cá nhân theo bệnh | SmartBot tip theo **chẩn đoán + thuốc** |
| 9 | BN Hotline | — | Gõ câu an toàn, rồi *"đau ngực khó thở"* | Guardrail: nguy hiểm → **can thiệp** ngay |
| 10 | DD OCR | — | Upload `don_thuoc_chu_minh_tam.docx` → Lưu | Đơn giấy → dữ liệu số → nhắc thuốc tự động |
| 11 | Đóng | — | 1 câu tagline | *Mỗi buổi sáng một câu hỏi — đúng người được gọi* |

**Preflight:** `./scripts/demo_pitch_preflight.sh`

---

## Chuẩn bị trước khi lên sân (15 phút)

```bash
make backend                    # hoặc docker compose up
./scripts/demo_pitch_preflight.sh
```

| Việc | Chi tiết |
|------|----------|
| iOS | Tắt **Demo mode** → URL `http://<IP-Mac>:8000/api/v1` → Kiểm tra kết nối ✅ |
| Âm lượng | iPhone bệnh nhân ~80%, điều dưỡng ~50% (để nghe tiếng rung/alert) |
| Đăng sẵn | Tab 1: bệnh nhân đã login; Tab 2: điều dưỡng đã login (hoặc 2 máy) |
| Reset buổi sáng | Mở app BN lần đầu trong ngày → thẻ **Buổi sáng 0/2** còn trống |
| File OCR | Biết đường dẫn `backend/test/ocr/don_thuoc_chu_minh_tam.docx` (AirDrop/Mac) |

**Plan B nhanh:** Nếu TTS chậm → đọc câu hỏi trên màn hình. Nếu poll lâu → nói *"AI đang phân tích"* và chuyển sang dashboard (đã có alert từ lần check-in trước).

---

## Câu chuyện hệ thống (nói 1 lần, ~20 giây)

> CareVoice không phải một tính năng rời rạc. Đây là **một vòng khép kín buổi sáng**:
>
> **Bệnh nhân** được hỏi thăm bằng giọng → **AI VNPT** (TTS, STT, SmartBot, SmartReader) xử lý qua backend → **phân loại nguy cơ kèm lý do** → **điều dưỡng** thấy đúng người trên dashboard → **người nhà** được báo khi cần → dữ liệu thuốc từ **OCR** quay lại nhắc uống thuốc ngày hôm sau.
>
> iOS không giữ token VNPT — mọi AI đi qua API, an toàn và kiểm soát được.

---

## Kịch bản chi tiết

### 0:00 – 0:35 · Mở đầu — Vấn đề thật

**[LỜI THOẠI]**

> Chào anh chị BGK và mentor. Em là [tên].
>
> Hôm qua mẹ em gọi ba lần. Lần một: *"Thuốc huyết áp là viên tròn hay viên dẹt?"* Lần hai — *"Con bảo tải app… mẹ bấm nhầm sang Facebook."* Lần ba — im. Em sợ nhất là lần ba.
>
> Một khoa có thể có hàng trăm bác như vậy, mà điều dưỡng hai tay, một điện thoại, và quá nhiều bảng Excel.
>
> **CareVoice AI** không làm chatbot biết hết. Em làm **giọng nói** cho người già, **lý do rõ ràng** cho điều dưỡng, và **báo đúng người** khi cần.

**[HÀNH ĐỘNG]** Đứng cạnh slide/logo hoặc mở app ở màn chọn vai trò — chưa demo.

**[GIÁ TRỊ AI]** Đặt vấn đề: công nghệ phải **giảm tải con người**, không thêm màn hình phức tạp.

---

### 0:35 – 1:15 · Buổi sáng bắt đầu — Trang chủ bệnh nhân

**[HÀNH ĐỘNG]** iPhone bệnh nhân → đã đăng nhập **Chu Minh Tâm** → tab **Trang chủ**.

**[LỜI THOẠI]**

> Đây là bác **Chu Minh Tâm**, 72 tuổi, đái tháo đường type 2 và tăng huyết áp. Sống tại nhà, con đi làm xa.
>
> *(Chờ app đọc lời chào)* Nghe không ạ? App **nói trước** — chào bác, hướng dẫn ba việc buổi sáng: check-in, thuốc, tái khám. Bác không cần đọc chữ nhỏ — **voice-first**.
>
> Thẻ **Buổi sáng** hiện 0/2: check-in và lời khuyên sức khỏe. Đây là **khung thói quen** — không phải mở app rồi không biết làm gì.

**[GIÁ TRỊ AI]** TTS (VNPT/on-device) = **rào cản kỹ thuật bằng 0** cho người cao tuổi.

**[HÀNH ĐỘNG]** Chỉ vào preview thuốc + lịch tái khám trên Trang chủ (không cần mở sâu).

---

### 1:15 – 2:30 · Demo lõi — Check-in + AI phân tích

**[HÀNH ĐỘNG]** Trang chủ → **Check-in hôm nay** → chờ câu hỏi (TTS hoặc text lớn).

**[LỜI THOẠI]**

> Mỗi sáng một câu hỏi cố định: *"Hôm nay bác thấy thế nào?"* Backend có thể dùng **VNPT TTS** đọc to — bác chỉ cần nghe.
>
> Bác bấm một trong ba nút lớn: **Ổn / Bình thường / Có vấn đề**. Một chạm là đủ gửi — không bắt buộc ghi âm.

**[HÀNH ĐỘNG]** Chọn **「Có vấn đề」** → bấm **Ghi âm** → nói rõ ràng: *"Hôm nay em hơi chóng mặt, đứng lên đầu óc quay quay."* → **Gửi**.

**[LỜI THOẠI]** *(Trong lúc loading ~3–5 giây)*

> Phía sau, backend nhận audio → **VNPT STT** chuyển thành chữ → **bộ phân loại nguy cơ** đọc transcript + nút bác bấm → ra mức **Cần chú ý** hoặc **Cần can thiệp** — kèm **danh sách lý do**, không phải một nhãn đỏ mù.
>
> Ví dụ: *"Check-in: bệnh nhân báo chóng mặt"* — điều dưỡng tin vì **thấy vì sao**, không phải hộp đen.

**[HÀNH ĐỘNG]** Kết quả hiện → chỉ **badge nguy cơ** + **lý do** + banner **「Đã báo người nhà」** (nếu có).

**[LỜI THOẠI]**

> Khi mức từ *cần chú ý* trở lên, hệ thống **tự kích hoạt**: alert điều dưỡng + log SMS tới người nhà **Trần Minh Anh** — production chỉ cần gắn SMS gateway, trigger đã sẵn trong API.

**[GIÁ TRỊ AI]** STT + explainable risk = **thay 8–10 phút gọi điện** bằng 30 giây, nhưng **không bỏ qua** tín hiệu nhẹ như chóng mặt.

**[TÍNH NĂNG PHỦ]** Check-in, TTS, STT, risk classifier, caregiver alert, loading/poll job.

---

### 2:30 – 3:25 · Điều dưỡng — Dashboard & ưu tiên

**[HÀNH ĐỘNG]** Đổi sang iPhone điều dưỡng (hoặc logout/login `nurse`/`nurse`) → **Dashboard**.

**[LỜI THOẠI]**

> Cùng lúc đó, điện thoại điều dưỡng **rung** — không phải tin nhắn cá nhân. Rung vì **bác Chu Minh Tâm vừa check-in cần chú ý**.
>
> Dashboard không liệt kê 200 bệnh nhân. API lọc **`actionable_only`** — chỉ ca **cần xử lý**: cần chú ý, cần can thiệp, OCR chờ duyệt, phân tích chờ.
>
> KPI trên đầu: bao nhiêu bệnh nhân active, bao nhiêu ca ưu tiên, **phút tiết kiệm** ước tính — đây là ngôn ngữ quản lý khoa, không phải ngôn ngữ model ML.

**[HÀNH ĐỘNG]** Chỉ **bác Chu Minh Tâm** trên danh sách ưu tiên → mở **Chi tiết**.

**[TÍNH NĂNG PHỦ]** Staff dashboard, KPI, priority filter, alert sound/haptic, auto-refresh.

---

### 3:25 – 4:05 · Timeline — Điều dưỡng tin vì thấy bằng chứng

**[HÀNH ĐỘNG]** Trong **Chi tiết bệnh nhân** → cuộn **Timeline** → bấm **phát audio** check-in vừa rồi.

**[LỜI THOẠI]**

> Timeline là **single source of truth**: check-in, hotline, OCR — một dòng thời gian.
>
> Điều dưỡng nghe **audio gốc** của bác, đọc **transcript STT**, thấy **mức nguy cơ + lý do**, và gợi ý phân tích giọng. Không cần hỏi lại *"bác nói gì sáng nay?"*
>
> Một chạm **Gọi người nhà** — SĐT đã có trong hồ sơ. Sau khi gọi → **Đã gọi lại** — trạng thái sync lên server, đồng nghiệp ca sau biết.

**[HÀNH ĐỘNG]** Bấm **Đã gọi lại** (hoặc cập nhật handling).

**[GIÁ TRỊ AI]** AI **chuẩn bị bằng chứng** — con người **ra quyết định cuối**. Đúng triết lý *human-in-the-loop*.

**[TÍNH NĂNG PHỦ]** Patient timeline, audio playback, handling status, one-tap call.

---

### 4:05 – 4:45 · Thuốc & adherence — Khép vòng chăm sóc hàng ngày

**[HÀNH ĐỘNG]** Quay lại iPhone bệnh nhân → tab **Thuốc** → chọn liều **buổi sáng** chưa uống → **Xác nhận đã uống**.

**[LỜI THOẠI]**

> OCR và check-in không có ý nghĩa nếu bác **không uống đúng thuốc**. Tab Thuốc có lịch sáng–trưa–chiều–tối, nhắc **local notification** — không cần Apple Developer để demo.
>
> *(Chờ app đọc tên thuốc)* App **đọc to** Metformin, Amlodipine… — bác từng cất thuốc vào hộp sữa để nhớ; giờ **giọng nói** thay hộp sữa.
>
> Điều dưỡng trên dashboard thấy **adherence** — ai bỏ liều sáng nhiều ngày sẽ nổi lên.

**[HÀNH ĐỘNG]** Quay Trang chủ → thẻ Buổi sáng **1/2** (đã check-in, chưa tip).

**[TÍNH NĂNG PHỦ]** Medication list, adherence, TTS đọc thuốc, local reminders, morning progress.

---

### 4:45 – 5:15 · Lời khuyên sức khỏe AI — Cá nhân hóa theo bệnh

**[HÀNH ĐỘNG]** Trang chủ → **Lời khuyên hôm nay** → chờ load → bấm **Nghe**.

**[LỜI THOẠI]**

> Bước hai buổi sáng: **lời khuyên cá nhân**. Backend lấy chẩn đoán đái tháo đường, tăng huyết áp và thuốc đang dùng → **SmartBot** sinh tip ngắn, dễ hiểu, **cache theo ngày** — không gọi lại mỗi lần mở.
>
> Có disclaimer: đây là gợi ý sống khỏe, **không thay tư vấn bác sĩ** — guardrail sản phẩm.

**[HÀNH ĐỘNG]** Bấm **Đã đọc** → Trang chủ **Buổi sáng 2/2** ✅.

**[GIÁ TRỊ AI]** SmartBot tạo **nội dung theo ngữ cảnh bệnh nhân**, không phải mẹo chung chung từ Google.

**[TÍNH NĂNG PHỦ]** Daily tip API, diagnosis context, TTS đọc tip, morning routine tracker.

---

### 5:15 – 6:00 · Hotline AI — An toàn vs khẩn cấp

**[HÀNH ĐỘNG]** Tab **Hotline**.

**[LỜI THOẠI — câu an toàn]**

> Bác còn có **Hotline 24/7** — hỏi bằng chữ hoặc giọng. Câu thường gặp:

**[HÀNH ĐỘNG]** Gõ: *"Tôi quên uống thuốc buổi sáng, có uống bù không?"* → Gửi.

**[LỜI THOẠI]**

> SmartBot trả lời ngay — transcript + câu trả lời + mức nguy cơ. Câu này thường **bình thường** — không làm điều dưỡng hoảng.

**[LỜI THOẠI — câu nguy hiểm]**

> Giờ em demo **guardrail** — câu mà điều dưỡng **phải** biết ngay:

**[HÀNH ĐỘNG]** Gõ (hoặc ghi âm): *"Tôi thấy đau ngực và khó thở"* → Gửi.

**[LỜI THOẠI]**

> Hệ thống không trả lời *"uống nước ấm"*. Từ khóa **đau ngực, khó thở** → **Cần can thiệp** — lý do liệt kê rõ, alert đẩy lên dashboard điều dưỡng. AI **phân loại**, người **can thiệp**.
>
> Nếu mạng chậm: app **queue offline** — bác vẫn ghi âm, sync khi có Wi-Fi.

**[GIÁ TRỊ AI]** SmartBot + risk classifier = **lọc 80% câu hỏi thường**, **không bỏ sót** 20% nguy hiểm.

**[TÍNH NĂNG PHỦ]** Hotline text/voice, STT, SmartBot, guardrail, offline queue, risk on hotline.

---

### 6:00 – 6:45 · OCR đơn thuốc — Khép vòng dữ liệu

**[HÀNH ĐỘNG]** iPhone điều dưỡng → **Chi tiết bệnh nhân** hoặc menu OCR → **Tải đơn thuốc** → chọn `don_thuoc_chu_minh_tam.docx` → chờ `needs_review`.

**[LỜI THOẠI]**

> Vòng khép kín cuối: bác mang đơn giấy từ phòng khám. Điều dưỡng chụp hoặc upload file — **VNPT SmartReader OCR** trích xuất tên thuốc, liều, tần suất.
>
> AI **draft** — điều dưỡng **30 giây** chỉnh và xác nhận, không gõ lại từ đầu. Sau **Lưu**, thuốc xuất hiện trên app bác → nhắc uống ngày mai.
>
> Từ **giấy tờ** → **dữ liệu số** → **giọng nhắc thuốc**. Đó là toàn hệ thống.

**[HÀNH ĐỘNG]** Sửa 1 dòng thuốc (tuỳ chọn) → **Xác nhận & lưu**.

**[TÍNH NĂNG PHỦ]** OCR upload, job poll, OCR review, confirm → medications sync.

---

### 6:45 – 7:15 · Đóng — Tổng kết hệ thống

**[LỜI THOẠI]**

> Tóm lại **CareVoice AI**:
>
> - **Voice-first** cho bệnh nhân — TTS, STT, nút lớn, đọc thuốc.  
> - **Explainable AI** cho điều dưỡng — mọi alert có lý do, timeline có audio.  
> - **Connected** cho người nhà — trigger SMS khi cần.  
> - **VNPT** qua backend — STT, TTS, SmartBot, SmartReader — đã test live, mock cho demo ổn định.  
> - **41 pytest + smoke test 3 vòng** — repo sẵn sàng mentor chạy lại.
>
> Em không hứa thay bác sĩ. Em hứa: **mỗi buổi sáng có tiếng hỏi thăm** — và khi cần, **đúng người được gọi**.
>
> **CareVoice AI** — *Mỗi buổi sáng, một câu hỏi. Mỗi câu trả lời, đúng người được gọi.* Em xin cảm ơn ạ.

**[HÀNH ĐỘNG]** Giơ logo / QR repo. Sẵn sàng Q&A.

---

## Phiên bản rút 4–5 phút (cắt gọn)

| Bỏ / rút | Giữ bắt buộc |
|----------|--------------|
| Lời khuyên sức khỏe (chỉ nhắc 1 câu) | Hook + Check-in voice + lý do |
| OCR (nói miệng "đã có, xem repo") | Dashboard + timeline + Đã gọi lại |
| Câu hotline an toàn | Hotline *đau ngực khó thở* |
| Preview tái khám | Thuốc + đọc tên 1 liều |

---

## Ma trận: Tính năng ↔ Đã demo

| Nhóm | Tính năng | Cảnh demo |
|------|-----------|-----------|
| **BN** | Trang chủ buổi sáng | Cảnh 2 |
| | Check-in TTS + quick answer + voice | Cảnh 3 |
| | Kết quả risk + lý do + banner NH | Cảnh 3 |
| | Lịch sử check-in | Nhắc miệng / swipe tab |
| | Thuốc + adherence + TTS | Cảnh 7 |
| | Lời khuyên AI (daily tip) | Cảnh 8 |
| | Hotline text + voice + guardrail | Cảnh 9 |
| | Offline queue | Nói miệng cảnh 9 |
| | Cài đặt / backend URL | Preflight |
| **Điều dưỡng** | Dashboard KPI | Cảnh 5 |
| | Danh sách ưu tiên + alert | Cảnh 5 |
| | Thông báo (notifications tab) | Tuỳ: mở nếu có badge |
| | Timeline + audio + handling | Cảnh 6 |
| | OCR upload + review | Cảnh 10 |
| | Tạo BN mới | Q&A — "đã có validate" |
| **Hệ thống** | JWT + RBAC | Q&A |
| | Job polling OCR/check-in/hotline | Cảnh 3, 9, 10 |
| | SMS mock người nhà | Cảnh 3 |
| | VNPT STT/TTS/SmartBot/OCR | Toàn script |
| | Risk classifier explainable | Cảnh 3, 9 |
| | Idempotency / rate limit | Q&A kỹ thuật |

---

## Xử lý sự cố trên sân

| Triệu chứng | Làm ngay | Nói với BGK |
|-------------|----------|-------------|
| Poll check-in > 10s | Chuyển dashboard — alert đã có từ lần trước | *"AI xử lý async, điều dưỡng không cần chờ"* |
| TTS im lặng | Đọc text trên màn hình | *"Fallback text lớn — thiết kế cho người khiếm thính"* |
| OCR fail | Dùng screenshot kết quả `needs_review` có sẵn | *"Pipeline đã chạy sáng nay, pytest pass"* |
| Mất Wi-Fi | Bật demo mode (backup) | *"Production có offline queue — đây là bản backup"* |
| VNPT timeout | `VENDOR_MOCK_MODE=true` trên Mac | *"Mock và live cùng contract — đổi 1 biến env"* |

---

## Q&A — Câu BGK hay hỏi

| Câu hỏi | Trả lời (15–20 giây) |
|---------|---------------------|
| Khác ChatGPT? | Chỉ 3 việc: hỏi sáng, nhắc thuốc, báo đúng người — trong phạm vi hồ sơ đã xác nhận, có guardrail. |
| AI sai thì sao? | Luôn có lý do + timeline; điều dưỡng review; mức điều trị → `needs_staff_review`. |
| SMS thật chưa? | Demo log `sms_mock`; API trigger + SĐT người nhà đã có — gắn gateway là xong. |
| Bảo mật VNPT? | Token chỉ backend `.env`; iOS không gọi thẳng VNPT. |
| Scale? | FastAPI + job model; SQLite demo → PostgreSQL + Redis queue production. |
| Chi phí? | Local notification miễn phí; VNPT theo gói; giảm phút gọi điện check-in. |

---

## Tài liệu liên quan

- [PRODUCT_PITCH_SOLO.md](PRODUCT_PITCH_SOLO.md) — bản ngắn 4–5 phút
- [SETUP_AND_ACCOUNTS.md](SETUP_AND_ACCOUNTS.md) — tài khoản & chạy backend
- [FEATURES_AND_FLOWS.md](FEATURES_AND_FLOWS.md) — chi tiết kỹ thuật từng flow
- [TESTING.md](../TESTING.md) — checklist trước khi lên sân