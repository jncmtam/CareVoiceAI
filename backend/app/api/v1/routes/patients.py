from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_principal, vnpt_gateway_dep
from app.core.config import Settings, get_settings
from app.core.errors import APIError
from app.db.session import get_db
from app.integrations.vnpt import VNPTGateway
from app.models.enums import DocumentType, OcrMode
from app.schemas.ocr import (
    CancelJobRequest,
    CancelJobResponse,
    DocumentUploadResponse,
    OCRConfirmRequest,
    OCRConfirmResponse,
    OCRJobResponse,
)
from app.schemas.adherence import MedicationAdherenceRequest, MedicationAdherenceResponse
from app.schemas.patients import (
    AppointmentListResponse,
    MedicationListResponse,
    PatientCreateRequest,
    PatientDeleteResponse,
    PatientResponse,
    PatientUpdateRequest,
)
from app.services.medication_adherence import MedicationAdherenceService
from app.services.auth import AuthService, Principal
from app.services.documents import DocumentService
from app.services.patients import PatientService

router = APIRouter()


@router.post("/patients", response_model=PatientResponse, status_code=status.HTTP_201_CREATED)
async def create_patient(
    request: PatientCreateRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> PatientResponse:
    response = await PatientService(db).create_patient(request, principal)
    await db.commit()
    return response


@router.get("/patients/{patient_id}", response_model=PatientResponse)
async def get_patient(
    patient_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> PatientResponse:
    await AuthService(db, settings).require_patient_scope(principal, patient_id)
    return await PatientService(db).get_patient(patient_id, include_notes=principal.is_staff)


@router.patch("/patients/{patient_id}", response_model=PatientResponse)
async def update_patient(
    patient_id: str,
    request: PatientUpdateRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> PatientResponse:
    response = await PatientService(db).update_patient(patient_id, request, principal)
    await db.commit()
    return response


@router.delete("/patients/{patient_id}", response_model=PatientDeleteResponse)
async def delete_patient(
    patient_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> PatientDeleteResponse:
    response = await PatientService(db).deactivate_patient(patient_id, principal)
    await db.commit()
    return response


@router.get("/me/patient", response_model=PatientResponse)
async def my_patient(
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> PatientResponse:
    if not principal.patient_id:
        from app.core.errors import APIError

        raise APIError("forbidden", "Tài khoản không gắn với bệnh nhân.", 403)
    return await PatientService(db).get_patient(principal.patient_id, include_notes=False)


@router.get("/patients/{patient_id}/medications", response_model=MedicationListResponse)
async def patient_medications(
    patient_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> MedicationListResponse:
    await AuthService(db, settings).require_patient_scope(principal, patient_id)
    return await PatientService(db).medications(patient_id)


@router.get("/me/medications", response_model=MedicationListResponse)
async def my_medications(
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> MedicationListResponse:
    if not principal.patient_id:
        from app.core.errors import APIError

        raise APIError("forbidden", "Tài khoản không gắn với bệnh nhân.", 403)
    return await PatientService(db).medications(principal.patient_id)


@router.post("/me/medications/adherence", response_model=MedicationAdherenceResponse)
async def record_medication_adherence(
    request: MedicationAdherenceRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> MedicationAdherenceResponse:
    response = await MedicationAdherenceService(db).record(request, principal)
    await db.commit()
    return response


@router.get("/patients/{patient_id}/appointments", response_model=AppointmentListResponse)
async def patient_appointments(
    patient_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AppointmentListResponse:
    await AuthService(db, settings).require_patient_scope(principal, patient_id)
    return await PatientService(db).appointments(patient_id)


@router.get("/me/appointments", response_model=AppointmentListResponse)
async def my_appointments(
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> AppointmentListResponse:
    if not principal.patient_id:
        from app.core.errors import APIError

        raise APIError("forbidden", "Tài khoản không gắn với bệnh nhân.", 403)
    return await PatientService(db).appointments(principal.patient_id)


@router.post(
    "/patients/{patient_id}/documents",
    response_model=DocumentUploadResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def upload_document(
    patient_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    gateway: Annotated[VNPTGateway, Depends(vnpt_gateway_dep)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    document_type: Annotated[DocumentType, Form()],
    ocr_mode: Annotated[OcrMode, Form()],
    client_request_id: Annotated[str, Form()],
    file: Annotated[UploadFile, File()],
) -> DocumentUploadResponse:
    if not principal.is_staff:
        raise APIError("forbidden", "Chỉ nhân viên y tế được upload tài liệu y tế.", 403)
    response = await DocumentService(db, settings, gateway).upload_document(
        patient_id=patient_id,
        document_type=document_type,
        ocr_mode=ocr_mode,
        file=file,
        client_request_id=client_request_id,
        principal=principal,
    )
    await db.commit()
    return response


@router.get("/ocr/jobs/{job_id}", response_model=OCRJobResponse)
async def ocr_job(
    job_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    gateway: Annotated[VNPTGateway, Depends(vnpt_gateway_dep)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> OCRJobResponse:
    response = await DocumentService(db, settings, gateway).ocr_job(job_id)
    if response.patient_id:
        await AuthService(db, settings).require_patient_scope(principal, response.patient_id)
    return response


@router.post("/ocr/jobs/{job_id}/cancel", response_model=CancelJobResponse)
async def cancel_ocr_job(
    job_id: str,
    request: CancelJobRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    gateway: Annotated[VNPTGateway, Depends(vnpt_gateway_dep)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> CancelJobResponse:
    _ = request
    service = DocumentService(db, settings, gateway)
    current = await service.ocr_job(job_id)
    if current.patient_id:
        await AuthService(db, settings).require_patient_scope(principal, current.patient_id)
    response = await service.cancel_job(job_id)
    await db.commit()
    return response


@router.post(
    "/patients/{patient_id}/documents/{upload_id}/confirm_ocr",
    response_model=OCRConfirmResponse,
)
async def confirm_ocr(
    patient_id: str,
    upload_id: str,
    request: OCRConfirmRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    gateway: Annotated[VNPTGateway, Depends(vnpt_gateway_dep)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> OCRConfirmResponse:
    if not principal.is_staff:
        raise APIError("forbidden", "Chỉ nhân viên y tế được xác nhận OCR.", 403)
    response = await DocumentService(db, settings, gateway).confirm_ocr(
        patient_id=patient_id,
        upload_id=upload_id,
        request=request,
        principal=principal,
    )
    await db.commit()
    return response
