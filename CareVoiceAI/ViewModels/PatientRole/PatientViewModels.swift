import Combine
import Foundation

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
}

@MainActor
final class TodayCheckinViewModel: ObservableObject {
    @Published var state: LoadableState<Checkin> = .idle
    @Published var checkin: Checkin?
    @Published var pollingMessage: String?
    @Published var analysisResult: CheckinJobResponse?
    @Published var selectedQuickAnswerId: String?
    @Published var isSubmitting = false
    @Published var error: APIError?
    @Published var offlineMessage: String?

    @Published var recorder = AudioRecorderService()
    @Published var player = AudioPlaybackService()

    private let apiClient: APIClient
    private let reachability: ReachabilityMonitor
    private var pollingTask: Task<Void, Never>?
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

    deinit {
        pollingTask?.cancel()
    }

    func load() async {
        state = .loading(L10n.preparingQuestion)
        error = nil
        do {
            let response = try await apiClient.todayCheckin()
            checkin = response.checkin
            state = .loaded(response.checkin)
            if response.checkin.audioStatus == .generating {
                pollAudio(for: response.checkin.id)
            } else if let audioURL = response.checkin.audioUrl {
                Task {
                    _ = try? await AudioCache.shared.cachedFile(for: audioURL, cacheKey: response.checkin.audioCacheKey)
                }
            }
        } catch {
            let apiError = error as? APIError ?? .unknown(message: error.localizedDescription)
            self.error = apiError
            state = .failed(apiError)
        }
    }

    func playQuestion() async {
        guard let checkin, let audioURL = checkin.audioUrl else { return }
        do {
            let file = try await AudioCache.shared.cachedFile(for: audioURL, cacheKey: checkin.audioCacheKey)
            try player.play(fileURL: file)
        } catch {
            self.error = error as? APIError ?? .file(message: error.localizedDescription)
        }
    }

    func toggleRecording() async {
        if recorder.isRecording {
            recorder.stopRecording()
            return
        }
        do {
            try await recorder.startRecording()
        } catch {
            self.error = error as? APIError ?? .file(message: error.localizedDescription)
        }
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

        let answerId = quickAnswerId ?? selectedQuickAnswerId
        let audioURL = recorder.lastRecordingURL
        let duration = recorder.lastDuration > 0 ? recorder.lastDuration : nil

        guard reachability.isConnected else {
            do {
                try await OfflineUploadQueue.shared.enqueueCheckin(
                    checkinId: checkin.id,
                    audioURL: audioURL,
                    quickAnswerId: answerId,
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
                duration: duration
            )
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
            HapticsManager.success()
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
}

@MainActor
final class HotlineViewModel: ObservableObject {
    @Published var questionText = ""
    @Published var history: [HotlineHistoryItem] = []
    @Published var latestAnswer: String?
    @Published var needsStaffReview = false
    @Published var isLoading = false
    @Published var error: APIError?
    @Published var recorder = AudioRecorderService()
    @Published var player = AudioPlaybackService()

    private let apiClient: APIClient
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        self.init(apiClient: .shared)
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
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
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func toggleRecording() async {
        if recorder.isRecording {
            recorder.stopRecording()
            return
        }
        do {
            try await recorder.startRecording()
        } catch {
            self.error = error as? APIError ?? .file(message: error.localizedDescription)
        }
    }

    func sendVoice() async {
        guard let audioURL = recorder.lastRecordingURL else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response = try await apiClient.askHotlineVoice(patientId: nil, audioURL: audioURL, duration: recorder.lastDuration)
            await handle(response)
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    private func handle(_ response: HotlineQuestionResponse) async {
        if response.status == .completed {
            latestAnswer = response.answerText
            needsStaffReview = response.needsStaffReview ?? false
            HapticsManager.success()
            await loadHistory()
        } else if let questionId = Optional(response.questionId) {
            await poll(questionId: questionId)
        }
    }

    private func poll(questionId: String) async {
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
            }
            latestAnswer = result.answerText
            needsStaffReview = result.needsStaffReview ?? false
            HapticsManager.success()
            await loadHistory()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }
}

@MainActor
final class FaceVerificationViewModel: ObservableObject {
    @Published var statusText: String?
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
            statusText = String(format: L10n.text("face.session_created"), response.sessionId)
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }
}
