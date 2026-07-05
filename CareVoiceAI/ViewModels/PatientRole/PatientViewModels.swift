import Combine
import Foundation
import UIKit

@MainActor
final class PatientHomeViewModel: ObservableObject {
    @Published var checkinState: LoadableState<Checkin> = .idle
    @Published var medications: [Medication] = []
    @Published var appointments: [Appointment] = []
    @Published var error: APIError?

    private let apiClient: APIClient

    convenience init() {
        self.init(apiClient: .shared)
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func load() async {
        checkinState = .loading(L10n.loading)
        error = nil
        do {
            async let checkin: TodayCheckinResponse = apiClient.todayCheckin()
            async let medicationResponse: MedicationListResponse = apiClient.myMedications()
            async let appointmentResponse: AppointmentListResponse = apiClient.myAppointments()
            let values: (TodayCheckinResponse, MedicationListResponse, AppointmentListResponse) = try await (checkin, medicationResponse, appointmentResponse)
            checkinState = .loaded(values.0.checkin)
            medications = values.1.medications
            appointments = values.2.appointments
            await scheduleAppointmentRemindersIfNeeded()
            if let audioURL = values.0.checkin.audioUrl, values.0.checkin.audioStatus == .ready {
                Task {
                    _ = try? await AudioCache.shared.cachedFile(for: audioURL, cacheKey: values.0.checkin.audioCacheKey)
                }
            }
        } catch {
            let apiError = error as? APIError ?? .unknown(message: error.localizedDescription)
            self.error = apiError
            checkinState = .failed(apiError)
        }
    }

    private func scheduleAppointmentRemindersIfNeeded() async {
        let prefs = (try? await apiClient.notificationPreferences())?.preferences
        guard prefs?.appointmentRemindersEnabled != false else { return }
        _ = await NotificationManager.shared.requestPermissionAtValueMoment()
        await NotificationManager.shared.syncAppointmentReminders(appointments: appointments, enabled: true)
    }
}

@MainActor
final class TodayCheckinViewModel: ObservableObject {
    @Published var state: LoadableState<Checkin> = .idle
    @Published var checkin: Checkin?
    @Published var pollingMessage: String?
    @Published var analysisResult: CheckinJobResponse?
    @Published var selectedQuickAnswerId: String?
    @Published var draftTranscript = ""
    @Published var selectedIntent: RiskLevel?
    @Published var suggestedIntent: RiskLevel?
    @Published var hasVoiceReview = false
    @Published var isTranscribing = false
    @Published var isSubmitting = false
    @Published var error: APIError?
    @Published var offlineMessage: String?
    @Published var caregiverNotifiedAt: Date?
    @Published var caregiverName: String?

    @Published var recorder = AudioRecorderService()
    @Published var player = AudioPlaybackService()

    private let apiClient: APIClient
    private let reachability: ReachabilityMonitor
    private let speech = SpeechReminderService.shared
    private var pollingTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var autoPlayedQuestionCheckinId: String?

    convenience init() {
        self.init(apiClient: .shared, reachability: .shared)
    }

    init(apiClient: APIClient, reachability: ReachabilityMonitor) {
        self.apiClient = apiClient
        self.reachability = reachability
        recorder.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        player.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        speech.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var isAISpeaking: Bool {
        player.isPlaying || speech.isSpeaking
    }

    deinit {
        pollingTask?.cancel()
    }

    func load() async {
        state = .loading(L10n.preparingQuestion)
        error = nil
        do {
            async let checkinResponse: TodayCheckinResponse = apiClient.todayCheckin()
            async let profileResponse: PatientResponse = apiClient.myPatientProfile()
            async let historyResponse: CheckinHistoryResponse = apiClient.checkinHistory()
            let response = try await checkinResponse
            caregiverName = try await profileResponse.patient.caregiverName
            checkin = response.checkin
            state = .loaded(response.checkin)
            await restoreCompletedResultIfNeeded(
                checkin: response.checkin,
                history: try await historyResponse
            )
            if analysisResult == nil, response.checkin.audioStatus == .generating {
                pollAudio(for: response.checkin.id)
            } else {
                await prepareQuestionAudioIfNeeded(for: response.checkin)
                await autoPlayQuestionIfNeeded()
            }
        } catch {
            let apiError = error as? APIError ?? .unknown(message: error.localizedDescription)
            self.error = apiError
            state = .failed(apiError)
        }
    }

    private func restoreCompletedResultIfNeeded(checkin: Checkin, history: CheckinHistoryResponse) async {
        guard analysisResult == nil else { return }

        if let jobId = checkin.completedJobId {
            do {
                let job = try await apiClient.checkinJob(id: jobId)
                guard job.status == .completed else { return }
                analysisResult = job
                MorningRoutineTracker.shared.markCheckinDone()
                if job.risk?.needsStaffReview == true {
                    caregiverNotifiedAt = job.caregiverAlertSentAt ?? Date()
                }
                return
            } catch {
                // Fall back to lightweight history restore below.
            }
        }

        guard checkin.status == "completed",
              let todayItem = history.items.first(where: { Calendar.current.isDateInToday($0.checkedInAt) })
        else { return }

        let riskLevel = todayItem.riskLevel ?? .normal
        analysisResult = CheckinJobResponse(
            jobId: todayItem.id,
            responseId: todayItem.id,
            status: .completed,
            progress: 100,
            stage: "completed",
            displayMessage: todayItem.summaryForPatient,
            pollAfterSeconds: nil,
            transcript: nil,
            summary: todayItem.summaryForPatient ?? todayItem.patientMessage,
            risk: RiskAssessment(
                level: riskLevel,
                label: nil,
                reasons: nil,
                needsStaffReview: riskLevel != .normal
            ),
            staffAlertId: nil,
            caregiverAlertSentAt: riskLevel != .normal ? todayItem.checkedInAt : nil,
            completedAt: todayItem.checkedInAt
        )
        MorningRoutineTracker.shared.markCheckinDone()
        if riskLevel != .normal {
            caregiverNotifiedAt = analysisResult?.caregiverAlertSentAt ?? todayItem.checkedInAt
        }
    }

    func skipQuestionPlayback() {
        stopQuestionPlayback()
    }

    func autoPlayQuestionIfNeeded() async {
        guard analysisResult == nil, let checkin, checkin.status != "completed" else { return }
        guard autoPlayedQuestionCheckinId != checkin.id else { return }
        autoPlayedQuestionCheckinId = checkin.id
        await playQuestion()
    }

    func playQuestion() async {
        guard let checkin, analysisResult == nil else { return }
        stopQuestionPlayback()

        if checkin.audioStatus == .ready, let audioURL = checkin.audioUrl {
            do {
                let file = try await AudioCache.shared.cachedFile(for: audioURL, cacheKey: checkin.audioCacheKey)
                player.onFinished = { [weak self] in
                    self?.inviteVoiceResponse()
                }
                try player.play(fileURL: file)
                return
            } catch {
                // Fall through to on-device TTS when cached audio is unavailable.
            }
        }

        let question = checkin.questionText.cvTrimmed
        guard !question.isEmpty else { return }
        speech.speakCheckinQuestion(question) { [weak self] in
            self?.inviteVoiceResponse()
        }
    }

    private func inviteVoiceResponse() {
        guard analysisResult == nil, !recorder.isRecording else { return }
        speech.speak(L10n.text("patient.checkin.status_invite"))
    }

    func stopQuestionPlayback() {
        player.stop()
        speech.stop()
    }

    private func prepareQuestionAudioIfNeeded(for checkin: Checkin) async {
        guard checkin.audioStatus == .ready, let audioURL = checkin.audioUrl else { return }
        _ = try? await AudioCache.shared.cachedFile(for: audioURL, cacheKey: checkin.audioCacheKey)
    }

    func toggleRecording() async {
        if recorder.isRecording {
            recorder.stopRecording()
            await submitVoiceAfterRecording()
            return
        }
        stopQuestionPlayback()
        do {
            try await recorder.startRecording()
            HapticsManager.tap()
        } catch {
            self.error = APIError.from(error)
        }
    }

    func applyQuickAnswer(_ answer: QuickAnswer) {
        selectedQuickAnswerId = answer.id
        if recorder.lastRecordingURL == nil || draftTranscript.cvTrimmed.isEmpty {
            draftTranscript = presetTranscript(for: answer.id)
        }
        let answerIntent = intent(for: answer.id)
        selectedIntent = answerIntent
        suggestedIntent = answerIntent
        hasVoiceReview = true
        HapticsManager.tap()
    }

    func friendlyStatusLabel(for answerId: String, fallback: String) -> String {
        switch answerId {
        case "normal":
            return L10n.text("patient.checkin.status_well")
        case "no":
            return L10n.text("patient.checkin.status_normal")
        case "yes":
            return L10n.text("patient.checkin.status_issue")
        default:
            return fallback
        }
    }

    private func submitVoiceAfterRecording() async {
        guard let checkin, let audioURL = recorder.lastRecordingURL else { return }
        isTranscribing = true
        error = nil
        defer { isTranscribing = false }

        let duration = recorder.lastDuration > 0 ? recorder.lastDuration : nil
        do {
            let transcription = try await apiClient.transcribeCheckinAudio(
                checkinId: checkin.id,
                audioURL: audioURL,
                duration: duration
            )
            draftTranscript = transcription.transcript
            suggestedIntent = transcription.suggestedRiskLevel
            if let suggested = transcription.suggestedRiskLevel,
               selectedIntent == nil || suggested == .intervention {
                selectedIntent = suggested
            } else if selectedIntent == nil, let answerId = selectedQuickAnswerId {
                selectedIntent = intent(for: answerId)
            }
            hasVoiceReview = true
            HapticsManager.success()
        } catch {
            self.error = APIError.from(error)
        }
    }

    private func intent(for quickAnswerId: String) -> RiskLevel {
        switch quickAnswerId {
        case "yes":
            return .attention
        case "no", "normal":
            return .normal
        default:
            return .normal
        }
    }

    private func presetTranscript(for quickAnswerId: String) -> String {
        switch quickAnswerId {
        case "yes":
            return "Hôm nay tôi có vấn đề sức khỏe cần điều dưỡng xem."
        case "no":
            return "Hôm nay tôi thấy bình thường, không có triệu chứng lạ."
        case "normal":
            return "Hôm nay tôi thấy khỏe."
        default:
            return "Hôm nay tôi thấy bình thường."
        }
    }

    var canSubmitCheckin: Bool {
        selectedQuickAnswerId != nil
    }

    func confirmAndSubmit() async {
        hasVoiceReview = true
        await submit()
    }

    func playRecording() {
        guard let url = recorder.lastRecordingURL else { return }
        do {
            try player.play(fileURL: url)
        } catch {
            self.error = error as? APIError ?? .file(message: error.localizedDescription)
        }
    }

    func submit(quickAnswerId: String? = nil) async {
        guard let checkin else { return }
        isSubmitting = true
        error = nil
        offlineMessage = nil
        defer { isSubmitting = false }

        guard let answerId = quickAnswerId ?? selectedQuickAnswerId else { return }
        let audioURL = recorder.lastRecordingURL
        let duration = recorder.lastDuration > 0 ? recorder.lastDuration : nil
        let trimmedTranscript = draftTranscript.cvTrimmed
        let confirmedTranscript = trimmedTranscript.isEmpty ? nil : trimmedTranscript
        let declaredIntent = selectedIntent ?? intent(for: answerId)

        guard reachability.isConnected else {
            do {
                try await OfflineUploadQueue.shared.enqueueCheckin(
                    checkinId: checkin.id,
                    audioURL: audioURL,
                    quickAnswerId: answerId,
                    confirmedTranscript: confirmedTranscript,
                    patientDeclaredRiskLevel: declaredIntent,
                    duration: duration
                )
                offlineMessage = L10n.savedOffline
                HapticsManager.success()
            } catch {
                self.error = error as? APIError ?? .file(message: error.localizedDescription)
            }
            return
        }

        do {
            let response = try await apiClient.submitCheckin(
                checkinId: checkin.id,
                audioURL: audioURL,
                quickAnswerId: answerId,
                confirmedTranscript: confirmedTranscript,
                patientDeclaredRiskLevel: declaredIntent,
                duration: duration
            )
            hasVoiceReview = false
            KeyboardDismissal.endEditing()
            pollingMessage = response.message ?? L10n.analyzingResponse
            await pollAnalysis(jobId: response.jobId)
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    private func pollAudio(for checkinId: String) {
        pollingTask?.cancel()
        let apiClient = apiClient
        pollingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await AsyncPoller<CheckinAudioStatusResponse>().poll {
                    try await apiClient.checkinAudio(checkinId: checkinId)
                } isComplete: { response in
                    response.audioStatus == .ready || response.audioStatus == .failed
                } isFailure: { response in
                    response.audioStatus == .failed
                } serverDelay: { response in
                    response.pollAfterSeconds
                }
                if var current = self.checkin, result.audioStatus == .ready {
                    current = Checkin(
                        id: current.id,
                        patientId: current.patientId,
                        scheduledFor: current.scheduledFor,
                        status: current.status,
                        completedJobId: current.completedJobId,
                        questionText: current.questionText,
                        audioStatus: result.audioStatus,
                        audioUrl: result.audioUrl,
                        audioCacheKey: result.audioCacheKey,
                        ttsJobId: current.ttsJobId,
                        pollAfterSeconds: nil,
                        quickAnswers: current.quickAnswers,
                        expiresAt: current.expiresAt
                    )
                    self.checkin = current
                    self.state = .loaded(current)
                    await self.prepareQuestionAudioIfNeeded(for: current)
                    await self.autoPlayQuestionIfNeeded()
                }
            } catch {
                self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
            }
        }
    }

    private func pollAnalysis(jobId: String) async {
        do {
            let apiClient = apiClient
            let result = try await AsyncPoller<CheckinJobResponse>().poll {
                try await apiClient.checkinJob(id: jobId)
            } isComplete: { response in
                response.status == .completed || response.status == .failed
            } isFailure: { response in
                response.status == .failed
            } serverDelay: { response in
                response.pollAfterSeconds
            }
            analysisResult = result
            pollingMessage = nil
            MorningRoutineTracker.shared.markCheckinDone()
            let needsReview = result.risk?.needsStaffReview == true
            if needsReview {
                HapticsManager.warning()
                caregiverNotifiedAt = result.caregiverAlertSentAt ?? Date()
            } else {
                HapticsManager.success()
            }
            SpeechReminderService.shared.speakCheckinResult(
                summary: result.summary,
                needsStaffReview: needsReview
            )
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }
}

@MainActor
final class CheckinHistoryViewModel: ObservableObject {
    @Published var items: [CheckinHistoryItem] = []
    @Published var isLoading = false
    @Published var error: APIError?

    private let apiClient: APIClient

    convenience init() {
        self.init(apiClient: .shared)
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            items = try await apiClient.checkinHistory().items
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }
}

@MainActor
final class MedicationListViewModel: ObservableObject {
    @Published var medications: [Medication] = []
    @Published var isLoading = false
    @Published var error: APIError?

    private let apiClient: APIClient

    convenience init() {
        self.init(apiClient: .shared)
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            medications = try await apiClient.myMedications().medications
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func scheduleRemindersIfNeeded() async {
        _ = await NotificationManager.shared.requestPermissionAtValueMoment()
        let prefs = (try? await apiClient.notificationPreferences())?.preferences
        guard prefs?.medicationRemindersEnabled != false else { return }
        for medication in medications {
            await scheduleReminder(for: medication)
        }
    }

    func scheduleReminder(for medication: Medication) async {
        let times = medication.timesOfDay?.isEmpty == false ? medication.timesOfDay! : [.morning]
        for time in times {
            var components = DateComponents()
            components.hour = time.defaultHour
            components.minute = 0
            let prompt = SpeechReminderService.shared.medicationPrompt(name: medication.name, dosage: medication.dosage)
            NotificationManager.shared.scheduleMedicationReminder(
                id: "\(medication.id ?? medication.name)-\(time.rawValue)",
                title: prompt,
                dateComponents: components,
                medicationId: medication.id,
                slot: time.rawValue
            )
        }
    }
}

@MainActor
final class AppointmentListViewModel: ObservableObject {
    @Published var appointments: [Appointment] = []
    @Published var isLoading = false
    @Published var error: APIError?

    private let apiClient: APIClient

    convenience init() {
        self.init(apiClient: .shared)
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            appointments = try await apiClient.myAppointments().appointments
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func scheduleRemindersIfNeeded() async {
        let prefs = (try? await apiClient.notificationPreferences())?.preferences
        guard prefs?.appointmentRemindersEnabled != false else { return }
        _ = await NotificationManager.shared.requestPermissionAtValueMoment()
        await NotificationManager.shared.syncAppointmentReminders(appointments: appointments, enabled: true)
    }
}

@MainActor
final class HotlineViewModel: ObservableObject {
    @Published var questionText = ""
    @Published var history: [HotlineHistoryItem] = []
    @Published var latestAnswer: String?
    @Published var latestTranscript: String?
    @Published var latestRiskLevel: RiskLevel?
    @Published var latestReasons: [String] = []
    @Published var needsStaffReview = false
    @Published var isLoading = false
    @Published var isProcessing = false
    @Published var processingMessage: String?
    @Published var processingStatus: JobStatus?
    @Published var error: APIError?
    @Published var offlineMessage: String?
    @Published var hasPendingVoice = false
    @Published var recorder = AudioRecorderService()
    @Published var player = AudioPlaybackService()

    private var isSubmittingVoice = false
    private var pendingVoiceClientRequestId: String?
    private let apiClient: APIClient
    private let reachability: ReachabilityMonitor
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        self.init(apiClient: .shared, reachability: .shared)
    }

    init(apiClient: APIClient, reachability: ReachabilityMonitor) {
        self.apiClient = apiClient
        self.reachability = reachability
        recorder.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        player.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func loadHistory() async {
        do {
            history = try await apiClient.hotlineHistory().items
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func sendText() async {
        guard !questionText.cvTrimmed.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response = try await apiClient.askHotlineText(patientId: nil, text: questionText.cvTrimmed)
            await handle(response)
            questionText = ""
            KeyboardDismissal.endEditing()
        } catch {
            self.error = APIError.from(error)
        }
    }

    func toggleRecording() async {
        if recorder.isRecording {
            recorder.stopRecording()
            if let url = recorder.lastRecordingURL {
                _ = await recorder.waitUntilRecordingFileIsReady(at: url)
            }
            pendingVoiceClientRequestId = UUID().uuidString
            hasPendingVoice = recorder.lastRecordingURL != nil
            HapticsManager.success()
            return
        }
        hasPendingVoice = false
        pendingVoiceClientRequestId = nil
        latestAnswer = nil
        latestTranscript = nil
        latestRiskLevel = nil
        latestReasons = []
        needsStaffReview = false
        SpeechReminderService.shared.stop()
        do {
            try await recorder.startRecording()
            HapticsManager.tap()
        } catch {
            self.error = APIError.from(error)
        }
    }

    func confirmSendVoice() async {
        guard hasPendingVoice, !isSubmittingVoice, !isLoading, !isProcessing else { return }
        await sendVoice()
        hasPendingVoice = false
        pendingVoiceClientRequestId = nil
    }

    func discardPendingVoice() {
        hasPendingVoice = false
        pendingVoiceClientRequestId = nil
        recorder.clearRecording()
    }

    func playPendingVoice() {
        guard let url = recorder.lastRecordingURL else { return }
        do {
            try player.play(fileURL: url)
        } catch {
            self.error = error as? APIError ?? .file(message: error.localizedDescription)
        }
    }

    private func sendVoice() async {
        guard let audioURL = recorder.lastRecordingURL else { return }
        guard !isSubmittingVoice else { return }
        isSubmittingVoice = true
        isLoading = true
        error = nil
        offlineMessage = nil
        defer {
            isLoading = false
            isSubmittingVoice = false
        }

        _ = await recorder.waitUntilRecordingFileIsReady(at: audioURL)

        let duration = recorder.lastDuration > 0 ? recorder.lastDuration : nil
        guard reachability.isConnected else {
            do {
                try await OfflineUploadQueue.shared.enqueueHotlineVoice(
                    patientId: nil,
                    audioURL: audioURL,
                    duration: duration
                )
                recorder.clearRecording()
                hasPendingVoice = false
                offlineMessage = L10n.savedOffline
                HapticsManager.success()
            } catch {
                self.error = APIError.from(error)
            }
            return
        }

        do {
            let response = try await submitHotlineVoice(audioURL: audioURL, duration: duration)
            recorder.clearRecording()
            await handle(response)
        } catch {
            self.error = APIError.from(error)
        }
    }

    private func submitHotlineVoice(audioURL: URL, duration: TimeInterval?) async throws -> HotlineQuestionResponse {
        _ = await recorder.waitUntilRecordingFileIsReady(at: audioURL)
        let audioData = try Data(contentsOf: audioURL)
        try UploadLimits.validateAudio(data: audioData, fileName: audioURL.lastPathComponent)

        var clientRequestId = pendingVoiceClientRequestId ?? UUID().uuidString
        for attempt in 0..<3 {
            do {
                return try await apiClient.askHotlineVoice(
                    patientId: nil,
                    audioData: audioData,
                    fileName: audioURL.lastPathComponent,
                    mimeType: audioURL.uploadMimeType,
                    duration: duration,
                    clientRequestId: clientRequestId
                )
            } catch let error as APIError {
                if case .server(let code, _, let statusCode, _) = error,
                   code == "conflict", statusCode == 409, attempt < 2 {
                    clientRequestId = UUID().uuidString
                    pendingVoiceClientRequestId = clientRequestId
                    continue
                }
                throw error
            }
        }
        throw APIError.unknown(message: L10n.errorDefault)
    }

    private func handle(_ response: HotlineQuestionResponse) async {
        if response.status == .completed || response.status == .needsReview {
            applyResult(
                transcript: response.transcript,
                answer: response.answerText ?? (response.status == .needsReview ? L10n.text("hotline.staff_pending") : nil),
                riskLevel: response.riskLevel,
                reasons: response.reasons,
                needsStaffReview: response.needsStaffReview ?? (response.status == .needsReview)
            )
            HapticsManager.success()
            await loadHistory()
        } else if !response.questionId.isEmpty {
            await poll(questionId: response.questionId, initialStatus: response.status)
        }
    }

    private func poll(questionId: String, initialStatus: JobStatus) async {
        isProcessing = true
        processingStatus = initialStatus
        processingMessage = processingMessage(for: initialStatus)
        defer {
            isProcessing = false
            processingMessage = nil
            processingStatus = nil
        }

        do {
            let apiClient = apiClient
            let result = try await AsyncPoller<HotlineQuestionStatusResponse>().poll {
                try await apiClient.hotlineQuestion(id: questionId)
            } isComplete: { response in
                response.status == .completed || response.status == .failed
            } isFailure: { response in
                response.status == .failed
            } serverDelay: { response in
                response.pollAfterSeconds
            } onUpdate: { [weak self] response in
                self?.processingStatus = response.status
                self?.processingMessage = self?.processingMessage(for: response.status)
            }
            if result.status == .failed {
                throw APIError.unknown(message: L10n.text("hotline.processing_failed"))
            }
            applyResult(
                transcript: result.transcript,
                answer: result.answerText ?? (result.status == .needsReview ? L10n.text("hotline.staff_pending") : nil),
                riskLevel: result.riskLevel,
                reasons: result.reasons,
                needsStaffReview: result.needsStaffReview ?? (result.status == .needsReview)
            )
            HapticsManager.success()
            await loadHistory()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    private func applyResult(
        transcript: String?,
        answer: String?,
        riskLevel: RiskLevel?,
        reasons: [String]?,
        needsStaffReview: Bool
    ) {
        latestTranscript = transcript
        latestAnswer = answer
        latestRiskLevel = riskLevel
        latestReasons = reasons ?? []
        self.needsStaffReview = needsStaffReview
        if let answer, !answer.cvTrimmed.isEmpty {
            SpeechReminderService.shared.speak(answer)
        }
    }

    private func processingMessage(for status: JobStatus) -> String {
        switch status {
        case .transcribing:
            return L10n.text("hotline.transcribing")
        case .processing, .analyzing, .summarizing:
            return L10n.text("hotline.answering")
        default:
            return L10n.text("hotline.processing")
        }
    }
}

@MainActor
final class FaceVerificationViewModel: ObservableObject {
    @Published var statusText: String?
    @Published var sessionId: String?
    @Published var isVerified = false
    @Published var isLoading = false
    @Published var error: APIError?

    private let apiClient: APIClient
    private let session: SessionManager

    convenience init() {
        self.init(apiClient: .shared, session: .shared)
    }

    init(apiClient: APIClient, session: SessionManager) {
        self.apiClient = apiClient
        self.session = session
    }

    func start() async {
        guard let patientId = session.patientContext?.id else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response = try await apiClient.createFaceVerificationSession(patientId: patientId)
            sessionId = response.sessionId
            statusText = L10n.text("face.ready_capture")
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func upload(image: UIImage) async {
        guard let sessionId, let data = image.jpegData(compressionQuality: 0.85) else { return }
        isLoading = true
        error = nil
        statusText = L10n.text("face.uploading")
        defer { isLoading = false }
        do {
            let response = try await apiClient.uploadFaceVerification(sessionId: sessionId, imageData: data)
            statusText = response.message
            isVerified = response.status == "verified"
            if isVerified {
                MorningRoutineTracker.shared.markFaceVerifyDone()
            }
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }
}
