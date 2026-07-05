from __future__ import annotations

from hashlib import sha256

_MOCK_TIPS_BY_KEY: dict[str, list[str]] = {
    "type_2_diabetes": [
        "Hôm nay bác ăn chậm, nhai kỹ và ưu tiên rau xanh. Đo đường huyết trước bữa ăn nếu bác có máy đo.",
        "Bác nhớ uống đủ nước và đi bộ nhẹ 10–15 phút sau ăn. Tránh đồ ngọt, nước ngọt có gas.",
    ],
    "hypertension": [
        "Hôm nay bác ăn nhạt, hạn chế mắm muối. Khi đứng dậy, hãy ngồi vài giây để tránh chóng mặt.",
        "Bác theo dõi huyết áp vào cùng một giờ mỗi ngày. Nếu đau đầu kéo dài, gọi điều dưỡng.",
    ],
    "heart_failure": [
        "Hôm nay bác cân nước uống và ăn mặn vừa phải. Ngủ kê gối cao hơn nếu thấy khó thở khi nằm.",
    ],
    "default": [
        "Hôm nay bác uống thuốc đúng giờ, ăn đủ bữa và đi bộ nhẹ nếu sức khỏe cho phép.",
        "Bác nghỉ ngơi đủ, uống nước đều và gọi hotline nếu thấy triệu chứng lạ.",
    ],
}


def daily_tip_prompt(*, diagnoses: list[str], medications: list[str], tip_date: str) -> str:
    dx = ", ".join(diagnoses) if diagnoses else "chưa ghi nhận"
    meds = "; ".join(medications) if medications else "chưa có thuốc xác nhận"
    return (
        "Bạn là trợ lý chăm sóc sức khỏe cho bệnh nhân cao tuổi tại nhà. "
        f"Hôm nay là ngày {tip_date}. "
        f"Chẩn đoán/bệnh nền: {dx}. "
        f"Thuốc đang dùng: {meds}. "
        "Hãy viết ĐÚNG MỘT lời khuyên ngắn (tối đa 2 câu, tiếng Việt, dễ hiểu, thân thiện). "
        "Chỉ gợi ý sinh hoạt, ăn uống, vận động nhẹ an toàn. "
        "KHÔNG chẩn đoán mới, KHÔNG đổi liều thuốc, KHÔNG thay thế bác sĩ."
    )


def daily_tip_fallback(diagnoses: list[str], patient_id: str, tip_date: str) -> str:
    key = _tip_key(diagnoses)
    pool = _MOCK_TIPS_BY_KEY.get(key) or _MOCK_TIPS_BY_KEY["default"]
    index = int(sha256(f"{patient_id}:{tip_date}".encode()).hexdigest(), 16) % len(pool)
    return pool[index]


def _tip_key(diagnoses: list[str]) -> str:
    if not diagnoses:
        return "default"
    lower = " ".join(diagnoses).lower()
    if "đái tháo" in lower or "tiểu đường" in lower or "type 2" in lower:
        return "type_2_diabetes"
    if "huyết áp" in lower or "hypertension" in lower:
        return "hypertension"
    if "suy tim" in lower or "heart" in lower:
        return "heart_failure"
    return "default"