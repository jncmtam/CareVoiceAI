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

    private init() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
        let nextMonth = Calendar.current.date(byAdding: .day, value: 28, to: today) ?? today

        let patientOne = PatientProfile(
            id: "pat_001",
            patientCode: "BN-2026-0001",
            fullName: "Trần Văn Bình",
            dateOfBirth: "1958-03-20",
            gender: .male,
            phoneNumber: "+84901234567",
            caregiverName: "Trần Minh Anh",
            caregiverPhoneNumber: "+84987654321",
            diagnoses: ["Đái tháo đường type 2", "Tăng huyết áp"],
            latestRiskLevel: .intervention,
            latestCheckinAt: today,
            nextAppointmentAt: nextWeek,
            notes: "Nghe kém, ưu tiên gọi người nhà sau 19:00.",
            age: 68,
            isActive: true
        )
        let patientTwo = PatientProfile(
            id: "pat_002",
            patientCode: "BN-2026-0002",
            fullName: "Nguyễn Thị Hoa",
            dateOfBirth: "1966-09-12",
            gender: .female,
            phoneNumber: "+84903334455",
            caregiverName: "Phạm Quang Minh",
            caregiverPhoneNumber: "+84906667788",
            diagnoses: ["Suy tim", "Rối loạn lipid máu"],
            latestRiskLevel: .attention,
            latestCheckinAt: yesterday,
            nextAppointmentAt: nextMonth,
            notes: "Cần nhắc uống thuốc buổi tối.",
            age: 60,
            isActive: true
        )
        let patientThree = PatientProfile(
            id: "pat_003",
            patientCode: "BN-2026-0003",
            fullName: "Lê Quốc Đạt",
            dateOfBirth: "1971-01-05",
            gender: .male,
            phoneNumber: "+84908889900",
            caregiverName: nil,
            caregiverPhoneNumber: nil,
            diagnoses: ["Sau phẫu thuật khớp gối"],
            latestRiskLevel: .normal,
            latestCheckinAt: today,
            nextAppointmentAt: Calendar.current.date(byAdding: .day, value: 14, to: today),
            notes: nil,
            age: 55,
            isActive: true
        )

        profiles = [
            patientOne.id: patientOne,
            patientTwo.id: patientTwo,
            patientThree.id: patientThree
        ]
        priorityPatients = [
            PatientSummary(
                patientId: patientOne.id,
                patientCode: patientOne.patientCode,
                fullName: patientOne.fullName,
                age: patientOne.age,
                diagnoses: patientOne.diagnoses,
                latestRiskLevel: .intervention,
                latestSummary: "Đau ngực nhẹ kèm khó thở khi đi lại, cần gọi lại để xác minh.",
                latestCheckinAt: today,
                handlingStatus: .new,
                unreadAlertCount: 2
            ),
            PatientSummary(
                patientId: patientTwo.id,
                patientCode: patientTwo.patientCode,
                fullName: patientTwo.fullName,
                age: patientTwo.age,
                diagnoses: patientTwo.diagnoses,
                latestRiskLevel: .attention,
                latestSummary: "Tăng cân 1.2kg trong 2 ngày, có phù nhẹ buổi chiều.",
                latestCheckinAt: yesterday,
                handlingStatus: .viewed,
                unreadAlertCount: 1
            ),
            PatientSummary(
                patientId: patientThree.id,
                patientCode: patientThree.patientCode,
                fullName: patientThree.fullName,
                age: patientThree.age,
                diagnoses: patientThree.diagnoses,
                latestRiskLevel: .normal,
                latestSummary: "Tập vận động tốt, không đau tăng thêm.",
                latestCheckinAt: today,
                handlingStatus: .resolved,
                unreadAlertCount: 0
            )
        ]
        timelines = [
            patientOne.id: [
                TimelineEntry(
                    id: "tl_001",
                    type: .checkinResponse,
                    occurredAt: today,
                    status: .completed,
                    riskLevel: .intervention,
                    summary: "Bệnh nhân hơi mệt, khó thở hơn bình thường",
                    transcript: "Hôm nay tôi hơi mệt, lúc đi lại thấy khó thở hơn bình thường.",
                    riskReasons: ["Khó thở tăng", "Có đau ngực", "Tiền sử tăng huyết áp"],
                    handlingStatus: .new,
                    staffAlertId: "alert_001",
                    displayMessage: nil,
                    jobId: nil
                ),
                TimelineEntry(
                    id: "tl_002",
                    type: .hotlineQuestion,
                    occurredAt: yesterday,
                    status: .completed,
                    riskLevel: .attention,
                    summary: "Hỏi về việc quên uống thuốc huyết áp buổi sáng.",
                    transcript: "Nếu sáng nay tôi quên uống thuốc thì tôi có nên uống bù vào buổi trưa không?",
                    riskReasons: ["Cần điều dưỡng xác nhận hướng dẫn dùng thuốc"],
                    handlingStatus: .viewed,
                    staffAlertId: nil,
                    displayMessage: nil,
                    jobId: nil
                )
            ],
            patientTwo.id: [
                TimelineEntry(
                    id: "tl_101",
                    type: .checkinResponse,
                    occurredAt: yesterday,
                    status: .completed,
                    riskLevel: .attention,
                    summary: "Phù chân nhẹ, cần theo dõi cân nặng và huyết áp.",
                    transcript: "Chân tôi sưng buổi chiều, sáng thì đỡ hơn.",
                    riskReasons: ["Phù ngoại vi", "Tiền sử suy tim"],
                    handlingStatus: .viewed,
                    staffAlertId: "alert_002",
                    displayMessage: nil,
                    jobId: nil
                )
            ],
            patientThree.id: [
                TimelineEntry(
                    id: "tl_201",
                    type: .checkinResponse,
                    occurredAt: today,
                    status: .processing,
                    riskLevel: nil,
                    summary: nil,
                    transcript: nil,
                    riskReasons: nil,
                    handlingStatus: nil,
                    staffAlertId: nil,
                    displayMessage: "Đang phân tích phản hồi mới nhất...",
                    jobId: "job_demo_checkin"
                )
            ]
        ]
        medicationsByPatient = [
            patientOne.id: DemoAPIService.defaultMedications,
            patientTwo.id: [
                Medication(
                    id: "med_201",
                    name: "Furosemide",
                    strength: "40mg",
                    dosage: "1 viên",
                    frequency: "Mỗi sáng",
                    timesOfDay: [.morning],
                    instructions: "Theo dõi cân nặng mỗi ngày.",
                    startDate: nil,
                    endDate: nil,
                    isActive: true
                )
            ],
            patientThree.id: []
        ]
        appointmentsByPatient = [
            patientOne.id: [
                Appointment(id: "apt_001", appointmentAt: nextWeek, department: "Nội tiết", doctorName: "BS. Lê Minh", status: "scheduled")
            ],
            patientTwo.id: [
                Appointment(id: "apt_002", appointmentAt: nextMonth, department: "Tim mạch", doctorName: "BS. Phạm An", status: "scheduled")
            ],
            patientThree.id: []
        ]
        checkinHistory = [
            CheckinHistoryItem(
                id: "hist_001",
                checkedInAt: today,
                status: "completed",
                riskLevel: .normal,
                patientMessage: "Bác đã gửi phản hồi hôm nay.",
                summaryForPatient: "Tình trạng ổn định, tiếp tục dùng thuốc theo đơn."
            ),
            CheckinHistoryItem(
                id: "hist_002",
                checkedInAt: yesterday,
                status: "completed",
                riskLevel: .attention,
                patientMessage: "Đã gửi điều dưỡng xem lại.",
                summaryForPatient: "Có dấu hiệu cần theo dõi thêm trong 24 giờ."
            )
        ]
        hotlineHistory = [
            HotlineHistoryItem(
                questionId: "hq_001",
                askedAt: yesterday,
                questionText: "Tôi quên uống thuốc sáng nay thì làm sao?",
                answerText: "Bác không tự ý uống bù nếu gần giờ liều tiếp theo. Điều dưỡng sẽ xem lại câu hỏi này.",
                needsStaffReview: true
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

    func loginPatientCode(patientCode: String, phoneLast4: String) async throws -> AuthResponse {
        authResponse(for: .patient)
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
        let id = "pat_\(UUID().uuidString.prefix(8))"
        let profile = PatientProfile(
            id: id,
            patientCode: request.patientCode,
            fullName: request.fullName,
            dateOfBirth: request.dateOfBirth,
            gender: request.gender,
            phoneNumber: request.phoneNumber,
            caregiverName: request.caregiverName,
            caregiverPhoneNumber: request.caregiverPhoneNumber,
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
                patientCode: request.patientCode,
                fullName: request.fullName,
                age: nil,
                diagnoses: request.diagnoses,
                latestRiskLevel: .normal,
                latestSummary: "Hồ sơ mới vừa được tạo, chờ tải tài liệu y tế.",
                latestCheckinAt: nil,
                handlingStatus: .new,
                unreadAlertCount: 0
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

    func myPatientProfile() async throws -> PatientResponse {
        try await patient(id: "pat_001")
    }

    func myMedications() async throws -> MedicationListResponse {
        MedicationListResponse(medications: medicationsByPatient["pat_001"] ?? [])
    }

    func medications(patientId: String) async throws -> MedicationListResponse {
        MedicationListResponse(medications: medicationsByPatient[patientId] ?? [])
    }

    func myAppointments() async throws -> AppointmentListResponse {
        AppointmentListResponse(appointments: appointmentsByPatient["pat_001"] ?? [])
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
            rawText: "Metformin 500mg ngày 2 lần. Amlodipine 5mg mỗi sáng.",
            draftMedications: [
                OCRDraftMedication(name: "Metformin", strength: "500mg", dosage: "1 viên", frequency: "Ngày 2 lần", timesOfDay: [.morning, .evening], instructions: "Uống sau ăn", confidence: 0.91),
                OCRDraftMedication(name: "Amlodipine", strength: "5mg", dosage: "1 viên", frequency: "Mỗi sáng", timesOfDay: [.morning], instructions: "Uống sau ăn sáng", confidence: 0.86)
            ],
            draftFollowUp: FollowUpDraft(
                appointmentAt: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
                department: "Nội tiết",
                doctorName: "BS. Lê Minh"
            ),
            warnings: ["Kiểm tra lại hàm lượng thuốc trước khi xác nhận."]
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
        TodayCheckinResponse(
            checkin: Checkin(
                id: "chk_demo_today",
                patientId: "pat_001",
                scheduledFor: "today",
                status: "open",
                questionText: "Hôm nay bác thấy sức khỏe thế nào? Có đau ngực, khó thở, sốt, ho hoặc dấu hiệu bất thường nào không?",
                audioStatus: .unavailable,
                audioUrl: nil,
                audioCacheKey: nil,
                ttsJobId: nil,
                pollAfterSeconds: nil,
                quickAnswers: [
                    QuickAnswer(id: "yes", label: "Có"),
                    QuickAnswer(id: "no", label: "Không"),
                    QuickAnswer(id: "normal", label: "Bình thường")
                ],
                expiresAt: Calendar.current.date(byAdding: .hour, value: 12, to: Date())
            )
        )
    }

    func checkinAudio(checkinId: String) async throws -> CheckinAudioStatusResponse {
        CheckinAudioStatusResponse(checkinId: checkinId, audioStatus: .unavailable, audioUrl: nil, audioCacheKey: nil, pollAfterSeconds: nil)
    }

    func submitCheckin(checkinId: String, audioURL: URL?, quickAnswerId: String?, duration: TimeInterval?) async throws -> SubmitCheckinResponse {
        SubmitCheckinResponse(
            responseId: "resp_demo_001",
            jobId: "job_demo_submit",
            status: .analyzing,
            pollAfterSeconds: 0.5,
            message: "Đã nhận câu trả lời. Hệ thống đang phân tích demo."
        )
    }

    func checkinJob(id: String) async throws -> CheckinJobResponse {
        CheckinJobResponse(
            jobId: id,
            responseId: "resp_demo_001",
            status: .completed,
            progress: 100,
            stage: "completed",
            displayMessage: "Đã phân tích xong.",
            pollAfterSeconds: nil,
            transcript: "Hôm nay tôi thấy bình thường, không đau ngực hay khó thở.",
            summary: "Tình trạng ổn định. Tiếp tục theo dõi và dùng thuốc theo đơn.",
            risk: RiskAssessment(level: .normal, label: "Bình thường", reasons: ["Không có triệu chứng cảnh báo"], needsStaffReview: false),
            staffAlertId: nil,
            completedAt: Date()
        )
    }

    func checkinHistory(cursor: String?) async throws -> CheckinHistoryResponse {
        CheckinHistoryResponse(items: checkinHistory, nextCursor: nil)
    }

    func dashboardOverview() async throws -> DashboardOverview {
        DashboardOverview(
            totalActivePatients: profiles.values.filter { $0.isActive != false }.count,
            needsAttentionToday: priorityPatients.filter { $0.latestRiskLevel == .attention }.count,
            needsInterventionToday: priorityPatients.filter { $0.latestRiskLevel == .intervention }.count,
            checkinCompletionRate: 0.82,
            pendingOcrJobs: 1,
            pendingAnalysisJobs: 1,
            updatedAt: Date()
        )
    }

    func priorityPatients(page: Int, query: String?, riskLevel: RiskLevel?) async throws -> PriorityPatientListResponse {
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
            return matchesQuery && matchesRisk
        }
        let perPage = 30
        let start = max(0, (page - 1) * perPage)
        let items = Array(filtered.dropFirst(start).prefix(perPage))
        return PriorityPatientListResponse(items: items, page: page, perPage: perPage, total: filtered.count, hasNext: start + perPage < filtered.count)
    }

    func patientTimeline(patientId: String, cursor: String?) async throws -> PatientTimelineResponse {
        guard let profile = profiles[patientId] else {
            throw APIError.server(code: "not_found", message: "Không tìm thấy timeline demo.", statusCode: 404, traceId: nil)
        }
        let header = TimelinePatientHeader(
            id: profile.id,
            patientCode: profile.patientCode,
            fullName: profile.fullName,
            age: profile.age,
            latestRiskLevel: profile.latestRiskLevel
        )
        return PatientTimelineResponse(patient: header, items: timelines[patientId] ?? [], nextCursor: nil)
    }

    func updateHandling(patientId: String, entryId: String, status: HandlingStatus, note: String?) async throws -> HandlingUpdateResponse {
        if var entries = timelines[patientId], let index = entries.firstIndex(where: { $0.id == entryId }) {
            let old = entries[index]
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
                displayMessage: old.displayMessage,
                jobId: old.jobId
            )
            timelines[patientId] = entries
        }
        return HandlingUpdateResponse(
            entryId: entryId,
            handlingStatus: status,
            handledBy: HandledByUser(id: "usr_demo_staff", fullName: "Nguyễn Thị Lan"),
            handledAt: Date(),
            note: note
        )
    }

    func askHotlineText(patientId: String?, text: String) async throws -> HotlineQuestionResponse {
        let id = "hq_\(UUID().uuidString.prefix(8))"
        let answer = "Đây là phản hồi tham khảo từ CareVoice AI. Nếu triệu chứng nặng lên hoặc có dấu hiệu bất thường, bác nên liên hệ điều dưỡng/bác sĩ phụ trách."
        hotlineHistory.insert(
            HotlineHistoryItem(questionId: id, askedAt: Date(), questionText: text, answerText: answer, needsStaffReview: true),
            at: 0
        )
        return HotlineQuestionResponse(
            questionId: id,
            jobId: nil,
            status: .completed,
            answerText: answer,
            sourceScope: "demo",
            needsStaffReview: true,
            staffAlertId: "alert_demo_hotline",
            pollAfterSeconds: nil
        )
    }

    func askHotlineVoice(patientId: String?, audioURL: URL, duration: TimeInterval?) async throws -> HotlineQuestionResponse {
        try await askHotlineText(patientId: patientId, text: "Câu hỏi bằng giọng nói demo")
    }

    func hotlineQuestion(id: String) async throws -> HotlineQuestionStatusResponse {
        HotlineQuestionStatusResponse(
            questionId: id,
            status: .completed,
            transcript: "Câu hỏi demo đã được nhận.",
            answerText: "Điều dưỡng sẽ xem lại nếu câu hỏi liên quan đến điều chỉnh thuốc.",
            needsStaffReview: true,
            riskLevel: .attention,
            staffAlertId: "alert_demo_hotline",
            pollAfterSeconds: nil
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
        FaceVerificationSessionResponse(
            sessionId: "face_demo_001",
            status: "created",
            uploadUrl: nil,
            expiresAt: Calendar.current.date(byAdding: .minute, value: 15, to: Date())
        )
    }

    private func authResponse(for role: UserRole) -> AuthResponse {
        let user: AppUser
        let patientContext: PatientSessionContext?
        switch role {
        case .patient, .caregiver:
            user = AppUser(id: "usr_demo_patient", role: .patient, fullName: "Trần Văn Bình")
            patientContext = PatientSessionContext(id: "pat_001", patientCode: "BN-2026-0001", fullName: "Trần Văn Bình")
        case .nurse, .doctor, .admin:
            user = AppUser(id: "usr_demo_staff", role: .nurse, fullName: "Nguyễn Thị Lan", staffCode: "DD001", department: "Nội tiết")
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
