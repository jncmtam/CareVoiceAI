_DIAGNOSIS_LABELS: dict[str, str] = {
    "type_2_diabetes": "Đái tháo đường type 2",
    "hypertension": "Tăng huyết áp",
    "heart_failure": "Suy tim",
    "dyslipidemia": "Rối loạn lipid máu",
    "post_knee_surgery": "Sau phẫu thuật khớp gối",
    "copd": "Bệnh phổi tắc nghẽn mạn tính (COPD)",
    "asthma": "Hen phế quản",
    "parkinson": "Parkinson",
    "chronic_kidney_disease": "Suy thận mạn",
    "rheumatoid_arthritis": "Viêm khớp dạng thấp",
    "atrial_fibrillation": "Rối loạn nhịp tim",
    "osteoporosis": "Loãng xương",
    "hyperthyroidism": "Cường giáp (Basedow)",
}


def diagnosis_labels(codes: list[str] | None) -> list[str]:
    if not codes:
        return []
    labels: list[str] = []
    for code in codes:
        key = (code or "").strip().lower().replace(" ", "_")
        labels.append(_DIAGNOSIS_LABELS.get(key, code))
    return labels