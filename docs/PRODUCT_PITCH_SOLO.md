# Script thuyết trình — 1 người (~4–5 phút)

**Người trình bày:** Product/tech lead (một người vừa kể chuyện vừa demo).  
**Thiết bị:** 1 iPhone bệnh nhân + 1 iPhone điều dưỡng (hoặc 1 máy đổi role nhanh).  
**Chuẩn bị:** Đăng sẵn `patient`/`patient` (Chu Minh Tâm) và `nurse`/`nurse`. Bật âm lượng — **giọng đọc app** là điểm nhấn. Tắt demo mode, backend chạy trên Mac.

---

## 0:00 – 0:40 · Mở đầu

> Chào mọi người. Hôm qua mẹ tôi gọi ba lần. Lần một: *"Con ơi, thuốc huyết áp là viên tròn hay viên dẹt?"* Lần hai — *"Con nói app gì đó… mẹ bấm nhầm sang Facebook."* Lần ba — im. Tôi sợ nhất là lần ba.
>
> Một bệnh viện có thể có hàng trăm bác như mẹ tôi, mà điều dưỡng thì hai tay, một điện thoại, và quá nhiều bảng theo dõi.
>
> **CareVoice AI** không làm chatbot biết hết. Chúng tôi làm **giọng nói** cho người già, **lý do rõ ràng** cho điều dưỡng, và **tin nhắn đúng lúc** cho người nhà.

---

## 0:40 – 1:10 · Vấn đề

> Nhiều bác đái tháo đường, tim mạch sống tốt ở nhà — nhưng check-in mỗi sáng vẫn là gọi điện chăm sóc, 8–10 phút mỗi cuộc. Triệu chứng nhẹ dễ lọt. Triệu chứng nặng đôi khi đến muộn.
>
> Bác không ghét công nghệ. Bác ghét **chữ nhỏ**. CareVoice trả lời bằng **giọng nói** và nút **Có / Không / Bình thường** — cỡ to, đọc được cả khi quên kính.

---

## 1:10 – 2:20 · Demo 1 — Buổi sáng của bác Chu Minh Tâm

`[DEMO]` Mở app bệnh nhân → **Trang chủ**.

> Nghe không ạ? App **nói trước**: chào bác, hướng dẫn ba bước buổi sáng — check-in, thuốc, tái khám.

`[DEMO]` **Check-in hôm nay** → chọn **「Có」** hoặc ghi âm *"Hôm nay hơi chóng mặt"* → **Gửi**.

> AI không chỉ gắn nhãn đỏ. Nó ghi **vì sao**: bệnh nhân chọn có triệu chứng, báo chóng mặt. Điều dưỡng tin vì thấy lý do, không phải hộp đen.

`[DEMO]` Chờ kết quả → badge **Cần chú ý** + danh sách lý do + banner **「Đã báo người nhà」**.

> Lúc này người nhà **Trần Minh Anh** nhận log SMS mock từ backend — production gắn gateway thật, trigger đã có sẵn.

`[DEMO]` Đổi sang app điều dưỡng → **Dashboard**.

> Điện thoại rung — không phải tin nhắn crush. Rung vì **bác Chu Minh Tâm cần gọi lại**. Banner đỏ, lý do rõ, **một chạm gọi người nhà**.

---

## 2:20 – 3:00 · Demo 2 — Thuốc & Hotline

`[DEMO]` Tab **Thuốc** → xác nhận buổi sáng. App **đọc to** tên thuốc.

> Bác từng cất thuốc vào hộp sữa để nhớ. Giờ app nhắc bằng giọng — tick thêm bước **Buổi sáng 3/3**.

`[DEMO]` Tab **Hotline** → gõ hoặc ghi âm: *"Tôi thấy đau ngực và khó thở"*.

> STT chuyển thành chữ → SmartBot phân loại **Cần can thiệp**, liệt kê lý do, gửi điều dưỡng xem lại. Hoặc dùng file WAV mẫu `test/stt/STT.sample.wav` — transcript thật từ VNPT.

---

## 3:00 – 3:40 · Demo 3 — Điều dưỡng & OCR (tuỳ thời gian)

`[DEMO]` Mở hồ sơ **Chu Minh Tâm** → upload đơn thuốc `.docx` → OCR → chỉnh thuốc → lưu.

> Một vòng khép kín: đơn giấy → dữ liệu số → nhắc uống thuốc tự động. Điều dưỡng **30 giây** review thay vì gõ lại từ đầu.

`[DEMO]` Chỉ KPI dashboard — phút tiết kiệm, danh sách ưu tiên.

---

## 3:40 – 4:30 · Đóng

> CareVoice AI: **Voice-first** cho người già. **Explainable** cho điều dưỡng. **Connected** cho người nhà.
>
> Demo chạy được cả khi mạng khựng — offline queue cho ghi âm check-in và hotline.
>
> Chúng tôi không hứa thay bác sĩ. Chỉ hứa: **mỗi buổi sáng có tiếng hỏi thăm** — và khi cần, **đúng người được gọi**.
>
> **CareVoice AI** — *Mỗi buổi sáng, một câu hỏi. Mỗi câu trả lời, đúng người được gọi.* Cảm ơn ạ.

---

## Phụ lục — Xử lý câu hỏi giám khảo

| Câu hỏi | Trả lời gợi ý |
|---------|----------------|
| SMS thật chưa? | Demo ghi `sms_mock` trong DB; API trigger đã có, production gắn SMS gateway. |
| Khác ChatGPT? | Chỉ làm 3 việc: hỏi sáng, nhắc thuốc, báo đúng người khi cần — trong phạm vi hồ sơ đã xác nhận. |
| Wi-Fi chết? | Offline queue; bác vẫn ghi âm, sync khi có mạng. |
| AI có sai không? | Luôn `needs_staff_review` khi liên quan điều trị; guardrail từ khóa nguy hiểm. |
| Dùng VNPT thế nào? | Backend gọi STT/TTS/SmartBot; đã test live bằng `scripts/vnpt_sample_wav_demo.py`. |