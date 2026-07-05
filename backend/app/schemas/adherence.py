from app.schemas.common import APIModel


class MedicationAdherenceRequest(APIModel):
    medication_id: str
    slot: str
    taken: bool
    recorded_via: str = "voice"
    client_request_id: str | None = None


class MedicationAdherenceResponse(APIModel):
    medication_id: str
    slot: str
    taken: bool
    missed_doses_today: int
    message: str


class MedicationAdherenceSummary(APIModel):
    patient_id: str
    missed_doses_today: int