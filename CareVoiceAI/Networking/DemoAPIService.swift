import Foundation

nonisolated final class DemoAPIService: @unchecked Sendable {
    static let shared = DemoAPIService()

    private var profiles: [String: PatientProfile]
    private var priorityPatients: [PatientSummary]
    private var timelines: [String: [TimelineEntry]]
    private var medicationsByPatient: [String: [Medication]]
    private var appointmentsByPatient: [String: [Appointment]]
    private var checkinHistory: [CheckinHistoryItem]
    private var hotlineHistory: [HotlineHistoryItem]
    private var preferences = NotificationPreferences(
        checkinRemindersEnabled: true,
        medicationRemindersEnabled: true,
        appointmentRemindersEnabled: true,
        criticalStaffAlertsEnabled: true
    )
    private var lastCheckinQuickAnswer: String?
    private var lastConfirmedTranscript: String?
    private var lastDeclaredRisk: RiskLevel?
    private var lastCheckinJobId: String?
    private var lastCheckinHadAudio = false
    private var lastCheckinDuration: TimeInterval?
    private var processedCheckinJobs: Set<String> = []
    private var caregiverAlertsSent: [String: Date] = [:]
    private var faceSessionStatus: [String: String] = [:]
    private var missedDosesToday = 0
    private var patientCodeSequence = 10
    private var activePatientId = "pat_001"

    private init() {
        let catalog = DemoPatientSeed.make()
        profiles = catalog.profiles
        priorityPatients = catalog.priorityPatients
        timelines = catalog.timelines
        medicationsByPatient = catalog.medicationsByPatient
        appointmentsByPatient = catalog.appointmentsByPatient

        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        checkinHistory = [
            CheckinHistoryItem(
                id: "hist_002",
                checkedInAt: yesterday,
                status: "completed",
                riskLevel: .attention,
                patientMessage: "Điều dưỡng đã để lại lời nhắn cho bác.",
                summaryForPatient: "Có dấu hiệu cần theo dõi thêm trong 24 giờ.",
                staffNote: "Buổi sáng quên thuốc có thể uống bù trưa nếu chưa quá 6 tiếng. Nếu chóng mặt tăng, gọi hotline ngay."
            )
        ]
        hotlineHistory = [
            HotlineHistoryItem(
                questionId: "hq_001",
                askedAt: yesterday,
                mode: "text",
                questionText: "Tôi quên uống thuốc sáng nay thì làm sao?",
                transcript: "Tôi quên uống thuốc sáng nay thì làm sao?",
                answerText: "Bác không tự ý uống bù nếu gần giờ liều tiếp theo. Điều dưỡng sẽ xem lại câu hỏi này.",
                needsStaffReview: true,
                riskLevel: .attention,
                reasons: ["Câu hỏi liên quan hướng dẫn dùng thuốc cần nhân viên y tế xác nhận."]
            )
        ]
    }

    func loginStaff(login: String, password: String) async throws -> AuthResponse {
        authResponse(for: .nurse)
    }

    func requestPatientOTP(phoneNumber: String, patientCode: String?) async throws -> PatientOtpResponse {
        PatientOtpResponse(
            otpSessionId: "otp_demo",
            maskedPhoneNumber: mask(phoneNumber: phoneNumber),
            expiresIn: 300,
            canResendAfter: 30
        )
    }

    func verifyPatientOTP(sessionId: String, code: String) async throws -> AuthResponse {
        authResponse(for: .patient)
    }

    func loginPatient(login: String, password: String) async throws -> AuthResponse {
        guard login == "patient", password == "patient" else {
            throw APIError.server(
                code: "unauthorized",
                message: L10n.text("auth.invalid_patient_credentials"),
                statusCode: 401,
                traceId: nil
            )
        }
        activePatientId = "pat_001"
        return authResponse(for: .patient, profile: profiles["pat_001"])
    }

    func loginPatientCode(patientCode: String, phoneLast4: String) async throws -> AuthResponse {
        guard let profile = matchPatientProfile(patientCode: patientCode, phoneLast4: phoneLast4) else {
            throw APIError.server(
                code: "unauthorized",
                message: L10n.text("auth.invalid_patient_credentials"),
                statusCode: 401,
                traceId: nil
            )
        }
        activePatientId = profile.id
        return authResponse(for: .patient, profile: profile)
    }

    func refreshToken(_ refreshToken: String) async throws -> RefreshTokenResponse {
        RefreshTokenResponse(accessToken: "demo_access_token_refreshed", refreshToken: "demo_refresh_token", tokenType: "bearer", expiresIn: 3600)
    }

    func logout(refreshToken: String?) async throws {}

    func me() async throws -> CurrentUserResponse {
        let role = await MainActor.run {
            SessionManager.shared.selectedRole ?? .patient
        }
        let response = authResponse(for: role)
        return CurrentUserResponse(user: response.user, patient: response.patient)
    }

    func createPatient(_ request: PatientCreateRequest) async throws -> PatientResponse {
        let validation = PatientInputValidator.validateNewPatient(
            fullName: request.fullName,
            phoneNumber: request.phoneNumber,
            caregiverPhone: request.caregiverPhoneNumber ?? ""
        )
        if let firstError = validation.fieldErrors.values.first {
            throw APIError.server(code: "validation_error", message: firstError, statusCode: 422, traceId: nil)
        }

        let patientCode = generatePatientCode()
        let phoneNumber = PatientInputValidator.normalizePhoneNumber(request.phoneNumber)
        let caregiverPhone = request.caregiverPhoneNumber.map(PatientInputValidator.normalizePhoneNumber)

        if profiles.values.contains(where: { $0.phoneNumber == phoneNumber && $0.isActive != false }) {
            throw APIError.server(code: "conflict", message: L10n.text("validation.phone.duplicate"), statusCode: 409, traceId: nil)
        }

        let id = "pat_\(UUID().uuidString.prefix(8))"
        let profile = PatientProfile(
            id: id,
            patientCode: patientCode,
            fullName: request.fullName.cvTrimmed,
            dateOfBirth: request.dateOfBirth,
            gender: request.gender,
            phoneNumber: phoneNumber,
            caregiverName: request.caregiverName,
            caregiverPhoneNumber: caregiverPhone,
            diagnoses: request.diagnoses,
            latestRiskLevel: .normal,
            latestCheckinAt: nil,
            nextAppointmentAt: nil,
            notes: request.notes,
            age: nil,
            isActive: true
        )
        profiles[id] = profile
        priorityPatients.insert(
            PatientSummary(
                patientId: id,
                patientCode: patientCode,
                fullName: request.fullName.cvTrimmed,
                age: nil,
                diagnoses: request.diagnoses,
                latestRiskLevel: .normal,
                latestSummary: "Hồ sơ mới vừa được tạo, chờ tải tài liệu y tế.",
                latestCheckinAt: nil,
                handlingStatus: .new,
                unreadAlertCount: 0,
                alertReasons: nil,
                caregiverAlertSentAt: nil,
                missedMedicationDoses: nil,
                patientPhone: phoneNumber,
                caregiverPhone: caregiverPhone
            ),
            at: 0
        )
        timelines[id] = []
        medicationsByPatient[id] = []
        appointmentsByPatient[id] = []
        return PatientResponse(patient: profile)
    }

    func patient(id: String) async throws -> PatientResponse {
        guard let profile = profiles[id] else {
            throw APIError.server(code: "not_found", message: "Không tìm thấy bệnh nhân demo.", statusCode: 404, traceId: nil)
        }
        return PatientResponse(patient: profile)
    }

    func updatePatient(id: String, request: PatientUpdateRequest) async throws -> PatientResponse {
        guard var profile = profiles[id], profile.isActive != false else {
            throw APIError.server(code: "not_found", message: "Không tìm thấy bệnh nhân demo.", statusCode: 404, traceId: nil)
        }

        let nextPhone = request.phoneNumber.map(PatientInputValidator.normalizePhoneNumber) ?? profile.phoneNumber
        let nextCaregiverPhone = request.caregiverPhoneNumber.map(PatientInputValidator.normalizePhoneNumber) ?? profile.caregiverPhoneNumber

        if let phoneNumber = nextPhone,
           profiles.values.contains(where: { $0.id != id && $0.phoneNumber == phoneNumber && $0.isActive != false }) {
            throw APIError.server(code: "conflict", message: L10n.text("validation.phone.duplicate"), statusCode: 409, traceId: nil)
        }

        profile = PatientProfile(
            id: profile.id,
            patientCode: profile.patientCode,
            fullName: request.fullName?.cvTrimmed ?? profile.fullName,
            dateOfBirth: profile.dateOfBirth,
            gender: profile.gender,
            phoneNumber: nextPhone,
            caregiverName: request.caregiverName?.cvTrimmed ?? profile.caregiverName,
            caregiverPhoneNumber: nextCaregiverPhone,
            diagnoses: profile.diagnoses,
            latestRiskLevel: profile.latestRiskLevel,
            latestCheckinAt: profile.latestCheckinAt,
            nextAppointmentAt: profile.nextAppointmentAt,
            notes: request.notes ?? profile.notes,
            age: profile.age,
            isActive: profile.isActive
        )
        profiles[id] = profile
        if let index = priorityPatients.firstIndex(where: { $0.patientId == id }) {
            let current = priorityPatients[index]
            priorityPatients[index] = PatientSummary(
                patientId: current.patientId,
                patientCode: current.patientCode,
                fullName: profile.fullName,
                age: current.age,
                diagnoses: current.diagnoses,
                latestRiskLevel: current.latestRiskLevel,
                latestSummary: current.latestSummary,
                latestCheckinAt: current.latestCheckinAt,
                handlingStatus: current.handlingStatus,
                unreadAlertCount: current.unreadAlertCount,
                alertReasons: current.alertReasons,
                caregiverAlertSentAt: current.caregiverAlertSentAt,
                missedMedicationDoses: current.missedMedicationDoses,
                patientPhone: nextPhone,
                caregiverPhone: nextCaregiverPhone
            )
        }
        return PatientResponse(patient: profile)
    }

    func deletePatient(id: String) async throws -> PatientDeleteResponse {
        guard profiles[id] != nil else {
            throw APIError.server(code: "not_found", message: "Không tìm thấy bệnh nhân demo.", statusCode: 404, traceId: nil)
        }
        profiles.removeValue(forKey: id)
        priorityPatients.removeAll { $0.patientId == id }
        timelines.removeValue(forKey: id)
        medicationsByPatient.removeValue(forKey: id)
        appointmentsByPatient.removeValue(forKey: id)
        return PatientDeleteResponse(patientId: id, deleted: true)
    }

    func myPatientProfile() async throws -> PatientResponse {
        try await patient(id: activePatientId)
    }

    func myMedications() async throws -> MedicationListResponse {
        MedicationListResponse(medications: medicationsByPatient[activePatientId] ?? [])
    }

    func medications(patientId: String) async throws -> MedicationListResponse {
        MedicationListResponse(medications: medicationsByPatient[patientId] ?? [])
    }

    func myAppointments() async throws -> AppointmentListResponse {
        AppointmentListResponse(appointments: appointmentsByPatient[activePatientId] ?? [])
    }

    func appointments(patientId: String) async throws -> AppointmentListResponse {
        AppointmentListResponse(appointments: appointmentsByPatient[patientId] ?? [])
    }

    func uploadDocument(patientId: String, documentType: DocumentType, mode: OcrMode, fileURL: URL) async throws -> DocumentUploadResponse {
        DocumentUploadResponse(
            uploadId: "upl_demo_001",
            jobId: "ocr_demo_001",
            status: .queued,
            pollAfterSeconds: 0.4,
            message: "Đang đọc tài liệu demo."
        )
    }

    func ocrJob(id: String) async throws -> OCRJobResponse {
        OCRJobResponse(
            jobId: id,
            uploadId: "upl_demo_001",
            patientId: "pat_001",
            status: .needsReview,
            progress: 100,
            stage: "needs_review",
            pollAfterSeconds: nil,
            createdAt: Date(),
            updatedAt: Date(),
            rawText: "Bệnh nhân: Chu Minh Tâm. Bác sĩ: BS. Lê Minh. Metformin 500mg ngày 2 lần. Tái khám Nội tiết sau 14 ngày.",
            draftMedications: [
                OCRDraftMedication(name: "Metformin", strength: "500mg", dosage: "1 viên", frequency: "Ngày 2 lần", timesOfDay: [.morning, .evening], instructions: "Uống sau ăn", confidence: 0.91),
                OCRDraftMedication(name: "Amlodipine", strength: "5mg", dosage: "1 viên", frequency: "Mỗi sáng", timesOfDay: [.morning], instructions: "Uống sau ăn sáng", confidence: 0.86)
            ],
            draftPatient: OCRPatientDraft(
                fullName: profiles[activePatientId]?.fullName ?? "Chu Minh Tâm",
                phoneNumber: profiles[activePatientId]?.phoneNumber ?? "+84327628468",
                dateOfBirth: profiles[activePatientId]?.dateOfBirth,
                diagnoses: profiles[activePatientId]?.diagnoses,
                address: nil,
                primaryDoctorName: "BS. Lê Minh",
                confidence: 0.88
            ),
            draftFollowUp: FollowUpDraft(
                appointmentAt: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
                department: "Nội tiết",
                doctorName: "BS. Lê Minh"
            ),
            instructions: "Uống thuốc đủ liều, không tự ý ngưng thuốc. Theo dõi đường huyết buổi sáng.",
            warnings: [
                "Điều dưỡng kiểm tra và chỉnh sửa trước khi lưu vào hồ sơ.",
                "Kiểm tra lại hàm lượng thuốc trước khi xác nhận."
            ]
        )
    }

    func cancelOCRJob(id: String, reason: String) async throws -> CancelJobResponse {
        CancelJobResponse(jobId: id, status: .cancelled)
    }

    func confirmOCR(patientId: String, uploadId: String, request: OCRConfirmRequest) async throws -> OCRConfirmResponse {
        medicationsByPatient[patientId, default: []].append(contentsOf: request.medications)
        let document = MedicalDocument(id: uploadId, documentType: .prescription, status: "confirmed", confirmedAt: Date())
        return OCRConfirmResponse(document: document, medications: medicationsByPatient[patientId] ?? request.medications)
    }

    func todayCheckin() async throws -> TodayCheckinResponse {
        let submittedToday = lastCheckinJobId != nil
        return TodayCheckinResponse(
            checkin: Checkin(
                id: "chk_demo_today",
                patientId: activePatientId,
                scheduledFor: "today",
                status: submittedToday ? "completed" : "open",
                completedJobId: lastCheckinJobId,
                questionText: "Hôm nay bác thấy sức khỏe thế nào? Có đau ngực, khó thở, sốt, ho hoặc dấu hiệu bất thường nào không?",
                audioStatus: .unavailable,
                audioUrl: nil,
                audioCacheKey: nil,
                ttsJobId: nil,
                pollAfterSeconds: nil,
                quickAnswers: [
                    QuickAnswer(id: "normal", label: "Ổn"),
                    QuickAnswer(id: "no", label: "Bình thường"),
                    QuickAnswer(id: "yes", label: "Có vấn đề")
                ],
                expiresAt: Calendar.current.date(byAdding: .hour, value: 12, to: Date())
            )
        )
    }

    func checkinAudio(checkinId: String) async throws -> CheckinAudioStatusResponse {
        CheckinAudioStatusResponse(checkinId: checkinId, audioStatus: .unavailable, audioUrl: nil, audioCacheKey: nil, pollAfterSeconds: nil)
    }

    func transcribeCheckinAudio(checkinId: String, audioURL: URL?, duration: TimeInterval?) async throws -> CheckinTranscribeResponse {
        _ = checkinId
        _ = audioURL
        _ = duration
        let transcript = "Hôm nay tôi hơi chóng mặt sau khi uống thuốc, không đau ngực."
        return CheckinTranscribeResponse(
            transcript: transcript,
            suggestedRiskLevel: .attention,
            message: "Bác có thể chỉnh lại chữ và chọn mức cần báo trước khi gửi."
        )
    }

    func submitCheckin(
        checkinId: String,
        audioURL: URL?,
        quickAnswerId: String?,
        confirmedTranscript: String? = nil,
        patientDeclaredRiskLevel: RiskLevel? = nil,
        duration: TimeInterval?
    ) async throws -> SubmitCheckinResponse {
        _ = checkinId
        _ = audioURL
        _ = duration
        lastCheckinQuickAnswer = quickAnswerId ?? "normal"
        lastConfirmedTranscript = confirmedTranscript?.cvTrimmed
        lastDeclaredRisk = patientDeclaredRiskLevel
        lastCheckinHadAudio = audioURL != nil
        lastCheckinDuration = duration
        let jobId = "job_demo_\(UUID().uuidString.prefix(8))"
        lastCheckinJobId = jobId
        return SubmitCheckinResponse(
            responseId: "resp_demo_001",
            jobId: jobId,
            status: .analyzing,
            pollAfterSeconds: 0.5,
            message: confirmedTranscript == nil
                ? "Đã nhận câu trả lời. Hệ thống đang phân tích demo."
                : "Đã nhận xác nhận của bác. Điều dưỡng sẽ xem lại nếu cần."
        )
    }

    func checkinJob(id: String) async throws -> CheckinJobResponse {
        if processedCheckinJobs.contains(id) {
            return demoCheckinJobResponse(for: id, assessment: demoRiskAssessment(for: resolvedQuickAnswer(forJobId: id)))
        }

        let patientId = patientId(forJobId: id) ?? activePatientId
        let quickAnswer = patientId == activePatientId ? lastCheckinQuickAnswer : "normal"
        let assessment = demoRiskAssessment(for: quickAnswer, declaredLevel: lastDeclaredRisk)
        let now = Date()
        updateDemoPatientAfterCheckin(patientId: patientId, jobId: id, assessment: assessment, at: now)
        processedCheckinJobs.insert(id)
        return demoCheckinJobResponse(for: id, assessment: assessment, completedAt: now)
    }

    func checkinHistory(cursor: String?) async throws -> CheckinHistoryResponse {
        CheckinHistoryResponse(items: checkinHistory, nextCursor: nil)
    }

    func dashboardOverview() async throws -> DashboardOverview {
        DashboardOverview(
            totalActivePatients: profiles.values.filter { $0.isActive != false }.count,
            needsAttentionToday: priorityPatients.filter { Self.isActionable($0) && $0.latestRiskLevel == .attention }.count,
            needsInterventionToday: priorityPatients.filter { Self.isActionable($0) && $0.latestRiskLevel == .intervention }.count,
            checkinCompletionRate: 0.82,
            pendingOcrJobs: 1,
            pendingAnalysisJobs: 1,
            updatedAt: Date()
        )
    }

    func priorityPatients(
        page: Int,
        query: String?,
        riskLevel: RiskLevel?,
        actionableOnly: Bool = false
    ) async throws -> PriorityPatientListResponse {
        let normalizedQuery = query?.cvTrimmed.lowercased()
        let filtered = priorityPatients.filter { patient in
            let matchesQuery: Bool
            if let normalizedQuery, !normalizedQuery.isEmpty {
                matchesQuery = patient.fullName.lowercased().contains(normalizedQuery)
                    || patient.patientCode.lowercased().contains(normalizedQuery)
            } else {
                matchesQuery = true
            }
            let matchesRisk = riskLevel == nil || patient.latestRiskLevel == riskLevel
            let matchesActionable = !actionableOnly || Self.isActionable(patient)
            return matchesQuery && matchesRisk && matchesActionable
        }
        let sorted = Self.sortPriorityPatients(filtered)
        let perPage = 30
        let start = max(0, (page - 1) * perPage)
        let items = Array(sorted.dropFirst(start).prefix(perPage))
        return PriorityPatientListResponse(items: items, page: page, perPage: perPage, total: filtered.count, hasNext: start + perPage < filtered.count)
    }

    func patientTimeline(patientId: String, cursor: String?) async throws -> PatientTimelineResponse {
        guard let profile = profiles[patientId] else {
            throw APIError.server(code: "not_found", message: "Không tìm thấy timeline demo.", statusCode: 404, traceId: nil)
        }
        let summary = priorityPatients.first(where: { $0.patientId == patientId })
        let header = TimelinePatientHeader(
            id: profile.id,
            patientCode: profile.patientCode,
            fullName: profile.fullName,
            age: profile.age,
            latestRiskLevel: profile.latestRiskLevel,
            alertReasons: summary?.alertReasons,
            caregiverAlertSentAt: summary?.caregiverAlertSentAt ?? caregiverAlertsSent[patientId],
            missedMedicationDoses: summary?.missedMedicationDoses
        )
        return PatientTimelineResponse(patient: header, items: timelines[patientId] ?? [], nextCursor: nil)
    }

    func updateHandling(patientId: String, entryId: String, status: HandlingStatus, note: String?) async throws -> HandlingUpdateResponse {
        if var entries = timelines[patientId], let index = entries.firstIndex(where: { $0.id == entryId }) {
            let old = entries[index]
            let trimmedNote = note?.cvTrimmed
            entries[index] = TimelineEntry(
                id: old.id,
                type: old.type,
                occurredAt: old.occurredAt,
                status: old.status,
                riskLevel: old.riskLevel,
                summary: old.summary,
                transcript: old.transcript,
                riskReasons: old.riskReasons,
                handlingStatus: status,
                staffAlertId: old.staffAlertId,
                staffNote: trimmedNote?.isEmpty == false ? trimmedNote : old.staffNote,
                handledByName: trimmedNote?.isEmpty == false ? "Ngô Ngọc Triệu Mẫn" : old.handledByName,
                displayMessage: old.displayMessage,
                jobId: old.jobId,
                audioUrl: old.audioUrl,
                quickAnswerId: old.quickAnswerId,
                patientDeclaredRiskLevel: old.patientDeclaredRiskLevel,
                recordedDurationSeconds: old.recordedDurationSeconds
            )
            timelines[patientId] = entries
            if let trimmedNote, !trimmedNote.isEmpty,
               let historyIndex = checkinHistory.firstIndex(where: { $0.id == entryId }) {
                let historyItem = checkinHistory[historyIndex]
                checkinHistory[historyIndex] = CheckinHistoryItem(
                    id: historyItem.id,
                    checkedInAt: historyItem.checkedInAt,
                    status: historyItem.status,
                    riskLevel: historyItem.riskLevel,
                    patientMessage: "Điều dưỡng đã để lại lời nhắn cho bác.",
                    summaryForPatient: historyItem.summaryForPatient,
                    staffNote: trimmedNote
                )
            } else if let trimmedNote, !trimmedNote.isEmpty, !checkinHistory.isEmpty, patientId == "pat_001" {
                let historyItem = checkinHistory[0]
                checkinHistory[0] = CheckinHistoryItem(
                    id: historyItem.id,
                    checkedInAt: historyItem.checkedInAt,
                    status: historyItem.status,
                    riskLevel: historyItem.riskLevel,
                    patientMessage: "Điều dưỡng đã để lại lời nhắn cho bác.",
                    summaryForPatient: historyItem.summaryForPatient,
                    staffNote: trimmedNote
                )
            }
        }
        reconcilePatientRisk(patientId: patientId)
        return HandlingUpdateResponse(
            entryId: entryId,
            handlingStatus: status,
            handledBy: HandledByUser(id: "usr_demo_staff", fullName: "Ngô Ngọc Triệu Mẫn"),
            handledAt: Date(),
            note: note
        )
    }

    func askHotlineText(patientId: String?, text: String) async throws -> HotlineQuestionResponse {
        let id = "hq_\(UUID().uuidString.prefix(8))"
        let assessment = classifyHotlineSymptoms(text: text)
        hotlineHistory.insert(
            HotlineHistoryItem(
                questionId: id,
                askedAt: Date(),
                mode: "text",
                questionText: text,
                transcript: text,
                answerText: nil,
                needsStaffReview: true,
                riskLevel: assessment.riskLevel,
                reasons: assessment.reasons
            ),
            at: 0
        )
        return HotlineQuestionResponse(
            questionId: id,
            jobId: nil,
            status: .needsReview,
            transcript: text,
            answerText: nil,
            sourceScope: "staff_manual",
            needsStaffReview: true,
            riskLevel: assessment.riskLevel,
            reasons: assessment.reasons,
            staffAlertId: "alert_demo_hotline",
            pollAfterSeconds: nil
        )
    }

    func askHotlineVoice(patientId: String?, audioData: Data, duration: TimeInterval?) async throws -> HotlineQuestionResponse {
        _ = audioData
        return try await askHotlineVoice(patientId: patientId, audioURL: URL(fileURLWithPath: "/tmp/demo-hotline.m4a"), duration: duration)
    }

    func askHotlineVoice(patientId: String?, audioURL: URL, duration: TimeInterval?) async throws -> HotlineQuestionResponse {
        let transcript = mockHotlineTranscript(duration: duration)
        let id = "hq_\(UUID().uuidString.prefix(8))"
        let assessment = classifyHotlineSymptoms(text: transcript)
        hotlineHistory.insert(
            HotlineHistoryItem(
                questionId: id,
                askedAt: Date(),
                mode: "voice",
                questionText: nil,
                transcript: transcript,
                answerText: assessment.summary,
                needsStaffReview: assessment.needsStaffReview,
                riskLevel: assessment.riskLevel,
                reasons: assessment.reasons
            ),
            at: 0
        )
        return HotlineQuestionResponse(
            questionId: id,
            jobId: "hotline_job_demo",
            status: .completed,
            transcript: transcript,
            answerText: assessment.summary,
            sourceScope: "symptom_stt",
            needsStaffReview: assessment.needsStaffReview,
            riskLevel: assessment.riskLevel,
            reasons: assessment.reasons,
            staffAlertId: assessment.needsStaffReview ? "alert_demo_hotline" : nil,
            pollAfterSeconds: nil
        )
    }

    func hotlineQuestion(id: String) async throws -> HotlineQuestionStatusResponse {
        let item = hotlineHistory.first(where: { $0.questionId == id })
        let transcript = item?.transcript ?? "Câu hỏi demo đã được nhận."
        let assessment = classifyHotlineSymptoms(text: transcript)
        return HotlineQuestionStatusResponse(
            questionId: id,
            status: .completed,
            transcript: transcript,
            answerText: item?.answerText ?? assessment.summary,
            needsStaffReview: item?.needsStaffReview ?? assessment.needsStaffReview,
            riskLevel: item?.riskLevel ?? assessment.riskLevel,
            reasons: item?.reasons ?? assessment.reasons,
            staffAlertId: (item?.needsStaffReview ?? assessment.needsStaffReview) ? "alert_demo_hotline" : nil,
            pollAfterSeconds: nil
        )
    }

    private func mockHotlineTranscript(duration: TimeInterval?) -> String {
        let samples = [
            "Hôm nay tôi thấy bình thường, không đau ngực hay khó thở.",
            "Tôi quên uống thuốc sáng nay thì có uống bù không?",
            "Tôi thấy đau ngực và khó thở, có nên uống thuốc không?"
        ]
        let index = Int(duration ?? 0) % samples.count
        return samples[index]
    }

    private func classifyHotlineSymptoms(text: String) -> (
        summary: String,
        riskLevel: RiskLevel,
        reasons: [String],
        needsStaffReview: Bool
    ) {
        let lower = text.lowercased()
        var reasons: [String] = []
        if lower.contains("đau ngực") { reasons.append("Hotline: bệnh nhân báo đau ngực") }
        if lower.contains("khó thở") { reasons.append("Hotline: bệnh nhân báo khó thở") }
        if lower.contains("ngất") { reasons.append("Hotline: bệnh nhân báo ngất hoặc choáng") }
        if lower.contains("chóng mặt") { reasons.append("Hotline: bệnh nhân báo chóng mặt") }
        if lower.contains("mệt") { reasons.append("Hotline: bệnh nhân báo mệt bất thường") }
        if lower.contains("sốt") { reasons.append("Hotline: bệnh nhân báo sốt") }

        if reasons.contains(where: { $0.contains("đau ngực") || $0.contains("khó thở") || $0.contains("ngất") }) {
            return (
                "Bệnh nhân báo triệu chứng cảnh báo, cần nhân viên y tế gọi lại sớm.",
                .intervention,
                reasons,
                true
            )
        }
        if !reasons.isEmpty {
            return (
                "Bệnh nhân có dấu hiệu cần theo dõi, điều dưỡng sẽ xem lại phản hồi.",
                .attention,
                reasons,
                true
            )
        }
        return (
            "Tình trạng ổn định theo phản hồi của bác.",
            .normal,
            ["Không có triệu chứng cảnh báo trong phản hồi hôm nay"],
            false
        )
    }

    func hotlineHistory(patientId: String?, cursor: String?) async throws -> HotlineHistoryResponse {
        HotlineHistoryResponse(items: hotlineHistory, nextCursor: nil)
    }

    func registerDevice(
        role: UserRole,
        notificationChannel: NotificationChannel
    ) async throws -> DeviceRegistrationResponse {
        DeviceRegistrationResponse(
            deviceId: DeviceIdentity.deviceID,
            registered: true,
            notificationChannel: notificationChannel,
            remotePushEnabled: false,
            message: "Demo dùng local notification.",
            updatedAt: Date()
        )
    }

    func deleteDevice() async throws {}

    func notificationPreferences() async throws -> NotificationPreferencesResponse {
        NotificationPreferencesResponse(deviceId: DeviceIdentity.deviceID, preferences: preferences)
    }

    func updateNotificationPreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferencesResponse {
        self.preferences = preferences
        return NotificationPreferencesResponse(deviceId: DeviceIdentity.deviceID, preferences: preferences)
    }

    func createFaceVerificationSession(patientId: String) async throws -> FaceVerificationSessionResponse {
        let sessionId = "face_demo_\(UUID().uuidString.prefix(8))"
        faceSessionStatus[sessionId] = "not_started"
        return FaceVerificationSessionResponse(
            sessionId: sessionId,
            status: "not_started",
            uploadUrl: URL(string: "demo://face/\(sessionId)"),
            expiresAt: Calendar.current.date(byAdding: .minute, value: 15, to: Date())
        )
    }

    func faceVerificationStatus(sessionId: String) async throws -> FaceVerificationStatusResponse {
        let status = faceSessionStatus[sessionId] ?? "not_started"
        return FaceVerificationStatusResponse(
            sessionId: sessionId,
            status: status,
            verifiedAt: status == "verified" ? Date() : nil,
            needsStaffReview: false
        )
    }

    func uploadFaceVerification(sessionId: String, imageData: Data) async throws -> FaceVerificationUploadResponse {
        _ = imageData
        faceSessionStatus[sessionId] = "verified"
        return FaceVerificationUploadResponse(
            sessionId: sessionId,
            status: "verified",
            verifiedAt: Date(),
            needsStaffReview: false,
            message: "Xác thực khuôn mặt thành công. Bác có thể tiếp tục tái khám."
        )
    }

    func recordMedicationAdherence(medicationId: String, slot: String, taken: Bool) async throws -> MedicationAdherenceResponse {
        if !taken {
            missedDosesToday += 1
        } else if missedDosesToday > 0 {
            missedDosesToday -= 1
        }
        if let index = priorityPatients.firstIndex(where: { $0.patientId == "pat_001" }) {
            let current = priorityPatients[index]
            priorityPatients[index] = PatientSummary(
                patientId: current.patientId,
                patientCode: current.patientCode,
                fullName: current.fullName,
                age: current.age,
                diagnoses: current.diagnoses,
                latestRiskLevel: current.latestRiskLevel,
                latestSummary: current.latestSummary,
                latestCheckinAt: current.latestCheckinAt,
                handlingStatus: current.handlingStatus,
                unreadAlertCount: current.unreadAlertCount,
                alertReasons: current.alertReasons,
                caregiverAlertSentAt: current.caregiverAlertSentAt,
                missedMedicationDoses: missedDosesToday > 0 ? missedDosesToday : nil,
                patientPhone: current.patientPhone,
                caregiverPhone: current.caregiverPhone
            )
        }
        return MedicationAdherenceResponse(
            medicationId: medicationId,
            slot: slot,
            taken: taken,
            missedDosesToday: missedDosesToday,
            message: taken ? "Đã ghi nhận uống thuốc." : "Đã ghi nhận chưa uống thuốc."
        )
    }

    private func demoRiskAssessment(for quickAnswerId: String?, declaredLevel: RiskLevel? = nil) -> RiskAssessment {
        if let declaredLevel {
            return RiskAssessment(
                level: declaredLevel,
                label: declaredLevel == .intervention ? "Cần can thiệp" : (declaredLevel == .attention ? "Cần chú ý" : "Bình thường"),
                reasons: ["Bệnh nhân xác nhận: \(declaredLevel == .intervention ? "Cần can thiệp" : (declaredLevel == .attention ? "Cần chú ý" : "Bình thường"))"],
                needsStaffReview: declaredLevel != .normal
            )
        }
        switch quickAnswerId {
        case "yes":
            return RiskAssessment(
                level: .intervention,
                label: "Cần can thiệp",
                reasons: [
                    "Check-in: bệnh nhân chọn 'Có triệu chứng bất thường'",
                    "Check-in: bệnh nhân báo chóng mặt"
                ],
                needsStaffReview: true
            )
        case "no":
            return RiskAssessment(
                level: .normal,
                label: "Bình thường",
                reasons: ["Không có triệu chứng cảnh báo trong phản hồi hôm nay"],
                needsStaffReview: false
            )
        default:
            return RiskAssessment(
                level: .normal,
                label: "Bình thường",
                reasons: ["Không có triệu chứng cảnh báo trong phản hồi hôm nay"],
                needsStaffReview: false
            )
        }
    }

    private func demoTimelineEntry(
        id: String? = nil,
        from old: TimelineEntry? = nil,
        jobId: String,
        assessment: RiskAssessment,
        patientId: String,
        occurredAt: Date? = nil,
        status: JobStatus
    ) -> TimelineEntry {
        let quickAnswer = patientId == activePatientId ? lastCheckinQuickAnswer : "normal"
        let transcript = demoTranscript(for: quickAnswer)
        return TimelineEntry(
            id: id ?? old?.id ?? "tl_demo_\(UUID().uuidString.prefix(8))",
            type: old?.type ?? .checkinResponse,
            occurredAt: occurredAt ?? old?.occurredAt ?? Date(),
            status: status,
            riskLevel: assessment.level,
            summary: assessment.level == .normal
                ? "Tình trạng ổn định theo phản hồi check-in."
                : "Bệnh nhân có dấu hiệu cần điều dưỡng xem lại sớm.",
            transcript: transcript,
            riskReasons: assessment.reasons,
            handlingStatus: assessment.needsStaffReview ? .new : .resolved,
            staffAlertId: assessment.needsStaffReview ? "alert_demo_checkin" : nil,
            staffNote: old?.staffNote,
            handledByName: old?.handledByName,
            displayMessage: old?.displayMessage,
            jobId: jobId,
            audioUrl: patientId == activePatientId && lastCheckinHadAudio
                ? URL(string: "https://api.carevoice.local/media/demo/checkin_voice.m4a")
                : nil,
            quickAnswerId: quickAnswer,
            patientDeclaredRiskLevel: patientId == activePatientId ? lastDeclaredRisk : .normal,
            recordedDurationSeconds: patientId == activePatientId
                ? lastCheckinDuration.map { Int($0) }
                : nil,
            analysisHints: demoAnalysisHints(for: transcript)
        )
    }

    private func demoAnalysisHints(for transcript: String) -> [String]? {
        let lower = transcript.lowercased()
        var hints: [String] = []
        if lower.contains("chóng mặt") || lower.contains("mệt") {
            hints.append("Ngữ điệu: mệt mỏi")
        }
        if lower.contains("đau") {
            hints.append("Nội dung: đề cập đau/nhức")
        }
        return hints.isEmpty ? nil : hints
    }

    private func demoTranscript(for quickAnswerId: String?) -> String {
        if let confirmed = lastConfirmedTranscript, !confirmed.isEmpty {
            return confirmed
        }
        switch quickAnswerId {
        case "yes":
            return "Hôm nay tôi hơi mệt và chóng mặt khi đứng dậy."
        case "no":
            return "Không có triệu chứng bất thường hôm nay."
        default:
            return "Hôm nay tôi thấy bình thường, không đau ngực hay khó thở."
        }
    }

    private func demoCheckinJobResponse(
        for jobId: String,
        assessment: RiskAssessment,
        completedAt: Date = Date()
    ) -> CheckinJobResponse {
        let quickAnswer = resolvedQuickAnswer(forJobId: jobId)
        return CheckinJobResponse(
            jobId: jobId,
            responseId: "resp_demo_001",
            status: .completed,
            progress: 100,
            stage: "completed",
            displayMessage: "Đã phân tích xong.",
            pollAfterSeconds: nil,
            transcript: demoTranscript(for: quickAnswer),
            summary: assessment.level == .normal
                ? "Tình trạng ổn định. Tiếp tục theo dõi và dùng thuốc theo đơn."
                : "Bệnh nhân có dấu hiệu cần điều dưỡng xem lại sớm.",
            risk: assessment,
            staffAlertId: assessment.needsStaffReview ? "alert_demo_checkin" : nil,
            caregiverAlertSentAt: assessment.needsStaffReview ? completedAt : nil,
            completedAt: completedAt
        )
    }

    private func resolvedQuickAnswer(forJobId jobId: String) -> String? {
        let patientId = patientId(forJobId: jobId) ?? "pat_001"
        return patientId == activePatientId ? lastCheckinQuickAnswer : "normal"
    }

    private func patientId(forJobId jobId: String) -> String? {
        for (patientId, entries) in timelines {
            if entries.contains(where: { $0.jobId == jobId }) {
                return patientId
            }
        }
        return jobId == lastCheckinJobId ? activePatientId : nil
    }

    private func reconcilePatientRisk(patientId: String) {
        guard let index = priorityPatients.firstIndex(where: { $0.patientId == patientId }),
              let profile = profiles[patientId] else { return }

        let entries = timelines[patientId] ?? []
        let openEntries = entries.filter { entry in
            guard entry.status == .completed else { return false }
            guard let status = entry.handlingStatus else { return false }
            return status == .new || status == .viewed || status == .calledBack
        }

        let current = priorityPatients[index]
        let effectiveRisk: RiskLevel
        let effectiveHandling: HandlingStatus?
        let unread: Int
        let summary: String?

        if let topOpen = openEntries.max(by: { Self.riskScore($0.riskLevel) < Self.riskScore($1.riskLevel) }) {
            effectiveRisk = topOpen.riskLevel ?? .attention
            effectiveHandling = topOpen.handlingStatus
            unread = openEntries.filter { $0.handlingStatus == .new }.count
            summary = topOpen.summary
        } else if let latest = entries.first(where: { $0.status == .completed }) {
            let raw = latest.riskLevel ?? .normal
            effectiveRisk = latest.handlingStatus == .resolved ? Self.stabilizedRisk(raw) : raw
            effectiveHandling = .resolved
            unread = 0
            summary = latest.handlingStatus == .resolved
                ? "Đã xử lý xong. Tiếp tục theo dõi theo lịch."
                : latest.summary
        } else {
            effectiveRisk = .normal
            effectiveHandling = nil
            unread = 0
            summary = current.latestSummary
        }

        profiles[patientId] = PatientProfile(
            id: profile.id,
            patientCode: profile.patientCode,
            fullName: profile.fullName,
            dateOfBirth: profile.dateOfBirth,
            gender: profile.gender,
            phoneNumber: profile.phoneNumber,
            caregiverName: profile.caregiverName,
            caregiverPhoneNumber: profile.caregiverPhoneNumber,
            diagnoses: profile.diagnoses,
            latestRiskLevel: effectiveRisk,
            latestCheckinAt: profile.latestCheckinAt,
            nextAppointmentAt: profile.nextAppointmentAt,
            notes: profile.notes,
            age: profile.age,
            isActive: profile.isActive
        )

        priorityPatients[index] = PatientSummary(
            patientId: current.patientId,
            patientCode: current.patientCode,
            fullName: current.fullName,
            age: current.age,
            diagnoses: current.diagnoses,
            latestRiskLevel: effectiveRisk,
            latestSummary: summary,
            latestCheckinAt: current.latestCheckinAt,
            handlingStatus: effectiveHandling,
            unreadAlertCount: unread,
            alertReasons: current.alertReasons,
            caregiverAlertSentAt: current.caregiverAlertSentAt,
            missedMedicationDoses: current.missedMedicationDoses,
            patientPhone: current.patientPhone,
            caregiverPhone: current.caregiverPhone
        )
    }

    private static func isActionable(_ patient: PatientSummary) -> Bool {
        guard let status = patient.handlingStatus else { return false }
        return status == .new || status == .viewed || status == .calledBack
    }

    private static func riskScore(_ level: RiskLevel?) -> Int {
        switch level {
        case .intervention: return 3
        case .attention: return 2
        case .normal, .none: return 1
        }
    }

    private static func handlingScore(_ status: HandlingStatus?) -> Int {
        switch status {
        case .new: return 4
        case .viewed: return 3
        case .calledBack: return 2
        case .resolved: return 1
        case .none: return 0
        }
    }

    private static func sortPriorityPatients(_ patients: [PatientSummary]) -> [PatientSummary] {
        patients.sorted { lhs, rhs in
            let lhsRisk = riskScore(lhs.latestRiskLevel)
            let rhsRisk = riskScore(rhs.latestRiskLevel)
            if lhsRisk != rhsRisk { return lhsRisk > rhsRisk }

            let lhsHandling = handlingScore(lhs.handlingStatus)
            let rhsHandling = handlingScore(rhs.handlingStatus)
            if lhsHandling != rhsHandling { return lhsHandling > rhsHandling }

            return (lhs.latestCheckinAt ?? .distantPast) > (rhs.latestCheckinAt ?? .distantPast)
        }
    }

    private static func stabilizedRisk(_ level: RiskLevel) -> RiskLevel {
        level == .intervention ? .attention : .normal
    }

    private func matchPatientProfile(patientCode: String, phoneLast4: String) -> PatientProfile? {
        let normalizedCode = PatientInputValidator.normalizePatientCode(patientCode)
        return profiles.values.first { profile in
            profile.patientCode == normalizedCode
            && ((profile.phoneNumber?.hasSuffix(phoneLast4))! || (profile.caregiverPhoneNumber?.hasSuffix(phoneLast4) == true))
        }
    }

    private func completeTimelineJob(patientId: String, jobId: String, assessment: RiskAssessment, at date: Date) {
        guard var entries = timelines[patientId],
              let index = entries.firstIndex(where: { $0.jobId == jobId }) else { return }
        let old = entries[index]
        entries[index] = demoTimelineEntry(
            from: old,
            jobId: jobId,
            assessment: assessment,
            patientId: patientId,
            status: .completed
        )
        timelines[patientId] = entries
    }

    private func updateDemoPatientAfterCheckin(patientId: String, jobId: String, assessment: RiskAssessment, at date: Date) {
        completeTimelineJob(patientId: patientId, jobId: jobId, assessment: assessment, at: date)
        guard var profile = profiles[patientId] else { return }
        profile = PatientProfile(
            id: profile.id,
            patientCode: profile.patientCode,
            fullName: profile.fullName,
            dateOfBirth: profile.dateOfBirth,
            gender: profile.gender,
            phoneNumber: profile.phoneNumber,
            caregiverName: profile.caregiverName,
            caregiverPhoneNumber: profile.caregiverPhoneNumber,
            diagnoses: profile.diagnoses,
            latestRiskLevel: assessment.level,
            latestCheckinAt: date,
            nextAppointmentAt: profile.nextAppointmentAt,
            notes: profile.notes,
            age: profile.age,
            isActive: profile.isActive
        )
        profiles[patientId] = profile

        if assessment.needsStaffReview {
            caregiverAlertsSent[patientId] = date
        }

        if let index = priorityPatients.firstIndex(where: { $0.patientId == patientId }) {
            let current = priorityPatients[index]
            priorityPatients[index] = PatientSummary(
                patientId: current.patientId,
                patientCode: current.patientCode,
                fullName: current.fullName,
                age: current.age,
                diagnoses: current.diagnoses,
                latestRiskLevel: assessment.level,
                latestSummary: assessment.level == .normal
                    ? "Tình trạng ổn định theo phản hồi check-in."
                    : "Bệnh nhân có dấu hiệu cần điều dưỡng xem lại sớm.",
                latestCheckinAt: date,
                handlingStatus: assessment.needsStaffReview ? .new : .resolved,
                unreadAlertCount: assessment.needsStaffReview ? 1 : 0,
                alertReasons: assessment.reasons,
                caregiverAlertSentAt: assessment.needsStaffReview ? date : current.caregiverAlertSentAt,
                missedMedicationDoses: current.missedMedicationDoses,
                patientPhone: profile.phoneNumber,
                caregiverPhone: profile.caregiverPhoneNumber
            )
        }

        let historyId: String
        if timelines[patientId]?.contains(where: { $0.jobId == jobId }) == true {
            historyId = timelines[patientId]?.first(where: { $0.jobId == jobId })?.id ?? "tl_demo_\(jobId)"
        } else {
            let entry = demoTimelineEntry(
                id: "tl_demo_\(UUID().uuidString.prefix(8))",
                jobId: jobId,
                assessment: assessment,
                patientId: patientId,
                occurredAt: date,
                status: .completed
            )
            timelines[patientId, default: []].insert(entry, at: 0)
            historyId = entry.id
        }
        if patientId == "pat_001" {
            checkinHistory.insert(
                CheckinHistoryItem(
                    id: historyId,
                    checkedInAt: date,
                    status: "completed",
                    riskLevel: assessment.level,
                    patientMessage: "Bác đã gửi phản hồi hôm nay.",
                    summaryForPatient: assessment.level == .normal
                        ? "Tình trạng ổn định theo phản hồi check-in."
                        : "Bệnh nhân có dấu hiệu cần điều dưỡng xem lại sớm.",
                    staffNote: nil
                ),
                at: 0
            )
        }
    }

    private func authResponse(for role: UserRole, profile: PatientProfile? = nil) -> AuthResponse {
        let user: AppUser
        let patientContext: PatientSessionContext?
        switch role {
        case .patient, .caregiver:
            let active = profile ?? profiles[activePatientId] ?? profiles["pat_001"]
            user = AppUser(id: "usr_demo_patient", role: .patient, fullName: active?.fullName ?? "Bệnh nhân demo")
            patientContext = active.map {
                PatientSessionContext(id: $0.id, patientCode: $0.patientCode, fullName: $0.fullName)
            }
        case .nurse, .doctor, .admin:
            user = AppUser(id: "usr_demo_staff", role: .nurse, fullName: "Ngô Ngọc Triệu Mẫn", staffCode: "nurse", department: "Nội tiết")
            patientContext = nil
        }
        return AuthResponse(
            accessToken: "demo_access_token",
            refreshToken: "demo_refresh_token",
            tokenType: "bearer",
            expiresIn: 3600,
            user: user,
            patient: patientContext
        )
    }

    private func generatePatientCode() -> String {
        patientCodeSequence += 1
        let year = Calendar.current.component(.year, from: Date())
        return String(format: "VC-%d-%06d", year, patientCodeSequence)
    }

    private func mask(phoneNumber: String) -> String {
        let trimmed = phoneNumber.cvTrimmed
        guard trimmed.count > 4 else { return trimmed }
        return "+84******\(trimmed.suffix(4))"
    }

    private static var defaultMedications: [Medication] {
        [
            Medication(
                id: "med_001",
                name: "Metformin",
                strength: "500mg",
                dosage: "1 viên",
                frequency: "Ngày 2 lần",
                timesOfDay: [.morning, .evening],
                instructions: "Uống sau ăn sáng và tối.",
                startDate: nil,
                endDate: nil,
                isActive: true
            ),
            Medication(
                id: "med_002",
                name: "Amlodipine",
                strength: "5mg",
                dosage: "1 viên",
                frequency: "Mỗi sáng",
                timesOfDay: [.morning],
                instructions: "Uống vào cùng một giờ mỗi ngày.",
                startDate: nil,
                endDate: nil,
                isActive: true
            )
        ]
    }
}
