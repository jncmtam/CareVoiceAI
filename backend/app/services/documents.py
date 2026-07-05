from fastapi import UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.errors import APIError
from app.db.session import AsyncSessionLocal
from app.integrations.vnpt import VNPTGateway, get_vnpt_gateway
from app.models import Appointment, Job, MedicalDocument, Medication, Patient
from app.models.enums import DocumentType, JobStatus, JobType, OcrMode
from app.schemas.ocr import (
    CancelJobResponse,
    DocumentUploadResponse,
    OCRConfirmRequest,
    OCRConfirmResponse,
    OCRDraftMedication,
    OCRJobResponse,
)
from app.schemas.patients import OCRPatientDraft
from app.services.auth import Principal
from app.services.idempotency import IdempotencyService, request_hash
from app.services.job_runner import job_runner
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
            status=JobStatus.queued,
            progress=0,
            stage="queued",
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

        if self.settings.vendor_mock_mode:
            await self._process_ocr(document=document, job=job)
        else:
            job_runner.enqueue(
                lambda: run_ocr_job(job.id),
                label=f"ocr:{job.id}",
                delay_seconds=self.settings.background_job_start_delay_seconds,
            )

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
            draft_patient=OCRPatientDraft.model_validate(result["draft_patient"])
            if result.get("draft_patient")
            else None,
            draft_follow_up=result.get("draft_follow_up"),
            instructions=result.get("instructions"),
            warnings=result.get("warnings"),
            error_code=job.error_code,
            error_message=job.error_message,
            display_message=self._ocr_display_message(job),
        )

    def _ocr_display_message(self, job: Job) -> str | None:
        if job.status == JobStatus.failed:
            return job.error_message or "Không đọc được đơn thuốc. Vui lòng thử lại hoặc nhập tay."
        if job.status in {JobStatus.processing, JobStatus.queued, JobStatus.uploading}:
            return "Hệ thống đang đọc đơn thuốc..."
        return None

    async def cancel_job(self, job_id: str) -> CancelJobResponse:
        job = await self.session.get(Job, job_id)
        if not job or job.job_type != JobType.ocr:
            raise APIError("not_found", "Không tìm thấy OCR job.", 404)
        if job.status in {JobStatus.completed, JobStatus.needs_review}:
            raise APIError("conflict", "Job đã hoàn tất, không thể huỷ.", 409)
        await self.gateway.cancel_ocr(job.vendor_job_id)
        job.status = JobStatus.cancelled
        job.stage = "cancelled"
        job.cancelled_at = now_utc()
        job.poll_after_seconds = None
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

        patient = await self.session.get(Patient, patient_id)
        if patient and request.patient_draft:
            draft = request.patient_draft
            if draft.full_name:
                patient.full_name = draft.full_name
            if draft.phone_number:
                patient.phone_number = draft.phone_number
            if draft.date_of_birth:
                patient.date_of_birth = draft.date_of_birth
            if draft.address:
                patient.address = draft.address
            if draft.primary_doctor_name:
                patient.primary_doctor_name = draft.primary_doctor_name
            if draft.diagnoses:
                patient.diagnoses = draft.diagnoses

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
            if patient and (
                patient.next_appointment_at is None
                or request.follow_up.appointment_at < patient.next_appointment_at
            ):
                patient.next_appointment_at = request.follow_up.appointment_at

        note_parts: list[str] = []
        if request.instructions:
            note_parts.append(f"Dặn dò (đơn): {request.instructions.strip()}")
        if request.nurse_note:
            note_parts.append(request.nurse_note.strip())
        if patient and note_parts:
            merged = "\n".join(note_parts)
            patient.notes = f"{patient.notes}\n{merged}".strip() if patient.notes else merged

        document.status = "confirmed"
        document.confirmed_at = now_utc()
        document.confirmed_by_user_id = request.confirmed_by_user_id or principal.user_id
        document.nurse_note = "\n".join(note_parts) if note_parts else None
        job.status = JobStatus.completed
        job.stage = "confirmed"
        job.completed_at = now_utc()

        return OCRConfirmResponse(
            document=document_out(document),
            medications=[medication_out(item) for item in created],
        )

    async def process_ocr_job(self, job_id: str) -> None:
        job = await self.session.get(Job, job_id)
        if not job or not job.source_id:
            return
        document = await self.session.get(MedicalDocument, job.source_id)
        if not document:
            return
        await self._process_ocr(document=document, job=job)

    async def _process_ocr(self, *, document: MedicalDocument, job: Job) -> None:
        job.status = JobStatus.processing
        job.progress = 20
        job.stage = "ocr_scan"
        job.poll_after_seconds = 2

        file_bytes = None
        filename = document.file_name
        content_type = document.mime_type
        if document.storage_url:
            file_bytes, filename, content_type = await self.storage.read_bytes(document.storage_url)

        result, vendor_job_id = await self.gateway.scan_medical_document(
            file_url=document.storage_url,
            mode=document.ocr_mode.value,
            file_bytes=file_bytes,
            filename=filename,
            content_type=content_type,
            document_type=document.document_type.value,
        )
        if vendor_job_id:
            job.vendor_job_id = vendor_job_id

        payload = {
            "raw_text": result.raw_text,
            "draft_medications": result.draft_medications,
            "draft_patient": result.draft_patient,
            "draft_follow_up": result.draft_follow_up,
            "instructions": result.instructions,
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


async def run_ocr_job(job_id: str) -> None:
    settings = get_settings()
    async with AsyncSessionLocal() as session:
        service = DocumentService(session, settings, get_vnpt_gateway(settings))
        try:
            await service.process_ocr_job(job_id)
            await session.commit()
        except Exception as exc:
            await session.rollback()
            async with AsyncSessionLocal() as fail_session:
                job = await fail_session.get(Job, job_id)
                if job:
                    job.status = JobStatus.failed
                    job.stage = "failed"
                    job.error_code = "vendor_unavailable"
                    job.error_message = str(exc)
                    job.poll_after_seconds = None
                    await fail_session.commit()
            raise