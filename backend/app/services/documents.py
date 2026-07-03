
from fastapi import UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import APIError
from app.integrations.vnpt import VNPTGateway
from app.models import Appointment, Job, MedicalDocument, Medication
from app.models.enums import DocumentType, JobStatus, JobType, OcrMode
from app.schemas.ocr import (
    CancelJobResponse,
    DocumentUploadResponse,
    OCRConfirmRequest,
    OCRConfirmResponse,
    OCRDraftMedication,
    OCRJobResponse,
)
from app.services.auth import Principal
from app.services.idempotency import IdempotencyService, request_hash
from app.services.mappers import document_out, medication_out
from app.services.storage import StorageService
from app.utils.datetime import now_utc
from app.utils.ids import new_id


class DocumentService:
    def __init__(
        self,
        session: AsyncSession,
        settings: Settings,
        gateway: VNPTGateway,
    ) -> None:
        self.session = session
        self.settings = settings
        self.gateway = gateway
        self.storage = StorageService(settings)
        self.idempotency = IdempotencyService(session)

    async def upload_document(
        self,
        *,
        patient_id: str,
        document_type: DocumentType,
        ocr_mode: OcrMode,
        file: UploadFile,
        client_request_id: str,
        principal: Principal,
    ) -> DocumentUploadResponse:
        payload_hash = request_hash(
            {
                "patient_id": patient_id,
                "document_type": document_type.value,
                "ocr_mode": ocr_mode.value,
                "filename": file.filename,
            }
        )
        replay = await self.idempotency.get_replay(
            scope="document_upload",
            actor_id=principal.user_id,
            client_request_id=client_request_id,
            request_hash_value=payload_hash,
        )
        if replay:
            if replay.get("_conflict"):
                raise APIError("conflict", replay["error"], 409)
            return DocumentUploadResponse.model_validate(replay)

        storage_url, size = await self.storage.save_upload(file, folder=f"patients/{patient_id}/documents")
        job = Job(
            id=new_id("ocr_job"),
            job_type=JobType.ocr,
            status=JobStatus.processing,
            progress=20,
            stage="ocr_scan",
            poll_after_seconds=2,
            patient_id=patient_id,
        )
        document = MedicalDocument(
            id=new_id("upl"),
            patient_id=patient_id,
            document_type=document_type,
            ocr_mode=ocr_mode,
            status="uploaded",
            file_name=file.filename,
            mime_type=file.content_type,
            size_bytes=size,
            storage_url=storage_url,
            client_request_id=client_request_id,
            job_id=job.id,
        )
        job.source_id = document.id
        self.session.add_all([job, document])
        await self._process_ocr(document=document, job=job)
        response = DocumentUploadResponse(
            upload_id=document.id,
            job_id=job.id,
            status=JobStatus.queued,
            poll_after_seconds=2,
            message="Hệ thống đang đọc đơn thuốc. Điều dưỡng có thể quay lại sau.",
        )
        await self.idempotency.store(
            scope="document_upload",
            actor_id=principal.user_id,
            client_request_id=client_request_id,
            request_hash_value=payload_hash,
            response_status=202,
            response_body=response.model_dump(mode="json"),
        )
        return response

    async def ocr_job(self, job_id: str) -> OCRJobResponse:
        job = await self.session.get(Job, job_id)
        if not job or job.job_type != JobType.ocr:
            raise APIError("not_found", "Không tìm thấy OCR job.", 404)
        document = None
        if job.source_id:
            document = await self.session.get(MedicalDocument, job.source_id)
        result = job.result or {}
        return OCRJobResponse(
            job_id=job.id,
            upload_id=document.id if document else job.source_id,
            patient_id=job.patient_id,
            status=job.status,
            progress=job.progress,
            stage=job.stage,
            poll_after_seconds=job.poll_after_seconds,
            created_at=job.created_at,
            updated_at=job.updated_at,
            raw_text=result.get("raw_text"),
            draft_medications=[
                OCRDraftMedication.model_validate(item)
                for item in result.get("draft_medications", [])
            ]
            or None,
            draft_follow_up=result.get("draft_follow_up"),
            warnings=result.get("warnings"),
        )

    async def cancel_job(self, job_id: str) -> CancelJobResponse:
        job = await self.session.get(Job, job_id)
        if not job or job.job_type != JobType.ocr:
            raise APIError("not_found", "Không tìm thấy OCR job.", 404)
        if job.status in {JobStatus.completed, JobStatus.needs_review}:
            raise APIError("conflict", "Job đã hoàn tất, không thể huỷ.", 409)
        job.status = JobStatus.cancelled
        job.stage = "cancelled"
        job.cancelled_at = now_utc()
        return CancelJobResponse(job_id=job.id, status=job.status)

    async def confirm_ocr(
        self,
        *,
        patient_id: str,
        upload_id: str,
        request: OCRConfirmRequest,
        principal: Principal,
    ) -> OCRConfirmResponse:
        document = await self.session.get(MedicalDocument, upload_id)
        if not document or document.patient_id != patient_id:
            raise APIError("not_found", "Không tìm thấy tài liệu.", 404)
        job = await self.session.get(Job, request.job_id)
        if not job or job.id != document.job_id:
            raise APIError("not_found", "Không tìm thấy OCR job.", 404)
        if job.status != JobStatus.needs_review or document.status == "confirmed":
            raise APIError("conflict", "OCR chưa sẵn sàng hoặc đã được xác nhận.", 409)

        created: list[Medication] = []
        for item in request.medications:
            medication = Medication(
                id=item.id or new_id("med"),
                patient_id=patient_id,
                document_id=document.id,
                name=item.name,
                strength=item.strength,
                dosage=item.dosage,
                frequency=item.frequency,
                times_of_day=[v.value if hasattr(v, "value") else str(v) for v in item.times_of_day]
                if item.times_of_day
                else None,
                instructions=item.instructions,
                start_date=item.start_date,
                end_date=item.end_date,
                is_active=item.is_active if item.is_active is not None else True,
            )
            self.session.add(medication)
            created.append(medication)

        if request.follow_up and request.follow_up.appointment_at:
            appointment = Appointment(
                id=new_id("appt"),
                patient_id=patient_id,
                appointment_at=request.follow_up.appointment_at,
                department=request.follow_up.department,
                doctor_name=request.follow_up.doctor_name,
                status="scheduled",
            )
            self.session.add(appointment)

        document.status = "confirmed"
        document.confirmed_at = now_utc()
        document.confirmed_by_user_id = request.confirmed_by_user_id or principal.user_id
        document.nurse_note = request.nurse_note
        job.status = JobStatus.completed
        job.stage = "confirmed"
        job.completed_at = now_utc()

        return OCRConfirmResponse(
            document=document_out(document),
            medications=[medication_out(item) for item in created],
        )

    async def _process_ocr(self, *, document: MedicalDocument, job: Job) -> None:
        result = await self.gateway.scan_medical_document(
            file_url=document.storage_url,
            mode=document.ocr_mode.value,
        )
        payload = {
            "raw_text": result.raw_text,
            "draft_medications": result.draft_medications,
            "draft_follow_up": result.draft_follow_up,
            "warnings": result.warnings,
        }
        document.raw_text = result.raw_text
        document.draft_payload = payload
        document.status = "needs_review"
        job.status = JobStatus.needs_review
        job.progress = 100
        job.stage = "needs_review"
        job.poll_after_seconds = None
        job.result = payload
        job.completed_at = now_utc()

