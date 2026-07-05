# Tài nguyên test CareVoice Backend

Thư mục chứa **file mẫu** dùng cho pytest, script demo và kiểm tra tích hợp VNPT. Không phải thư mục pytest (`tests/` nằm cạnh đây).

## Cấu trúc

| Thư mục | Nội dung | Dùng cho |
|---------|----------|----------|
| `stt/` | `STT.sample.wav` — mono 48kHz, ~3s | STT live VNPT, hotline voice test |
| `ocr/` | `don_thuoc_chu_minh_tam.docx` + JSON kết quả mock | OCR contract test, generate script |
| `tts/` | `generated/` — output MP3 khi chạy demo TTS | `vnpt_sample_wav_demo.py` |
| `hotline/` | (dự phòng) audio/text mẫu hotline | Mở rộng test sau |

## Script liên quan

```bash
# STT + TTS + SmartBot với WAV mẫu
python scripts/vnpt_sample_wav_demo.py

# Tạo lại đơn thuốc docx mẫu
python scripts/generate_sample_prescription.py
```

## Pytest

Test code trong `backend/tests/` import đường dẫn qua:

```python
from tests.paths import test_asset
wav = test_asset("stt", "STT.sample.wav")
docx = test_asset("ocr", "don_thuoc_chu_minh_tam.docx")
```

## Git

- File mẫu `stt/`, `ocr/` **được commit**
- `tts/generated/` **bị ignore** (xem `.gitignore`)