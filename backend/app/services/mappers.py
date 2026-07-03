from app.models import Appointment as AppointmentModel
from app.models import MedicalDocument as MedicalDocumentModel
from app.models import Medication as MedicationModel
from app.models import Patient as PatientModel
from app.schemas.patients import Appointment, MedicalDocument, Medication, PatientProfile
from app.utils.datetime import age_from_birth_date


def patient_profile(patient: PatientModel, *, include_notes: bool = True) -> PatientProfile:
    return PatientProfile(
        id=patient.id,
        patient_code=patient.patient_code,
        full_name=patient.full_name,
        date_of_birth=patient.date_of_birth,
        gender=patient.gender,
        phone_number=patient.phone_number,
        caregiver_name=patient.caregiver_name,
        caregiver_phone_number=patient.caregiver_phone_number,
        diagnoses=patient.diagnoses,
        latest_risk_level=patient.latest_risk_level,
        latest_checkin_at=patient.latest_checkin_at,
        next_appointment_at=patient.next_appointment_at,
        notes=patient.notes if include_notes else None,
        age=age_from_birth_date(patient.date_of_birth),
        is_active=patient.is_active,
    )


def medication_out(medication: MedicationModel) -> Medication:
    return Medication(
        id=medication.id,
        name=medication.name,
        strength=medication.strength,
        dosage=medication.dosage,
        frequency=medication.frequency,
        times_of_day=medication.times_of_day,
        instructions=medication.instructions,
        start_date=medication.start_date,
        end_date=medication.end_date,
        is_active=medication.is_active,
    )


def appointment_out(appointment: AppointmentModel) -> Appointment:
    return Appointment(
        id=appointment.id,
        appointment_at=appointment.appointment_at,
        department=appointment.department,
        doctor_name=appointment.doctor_name,
        status=appointment.status,
    )


def document_out(document: MedicalDocumentModel) -> MedicalDocument:
    return MedicalDocument(
        id=document.id,
        document_type=document.document_type,
        status=document.status,
        confirmed_at=document.confirmed_at,
    )

