import Foundation

@MainActor
final class StaffDashboardViewModel: ObservableObject {
    @Published var overview: DashboardOverview?
    @Published var patients: [PatientSummary] = []
    @Published var selectedRiskLevel: RiskLevel?
    @Published var query = ""
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasNext = false
    @Published var error: APIError?

    private let apiClient: APIClient
    private var page = 1

    convenience init() {
        self.init(apiClient: .shared)
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func load(reset: Bool = true) async {
        if reset {
            page = 1
            isLoading = true
        } else {
            isLoadingMore = true
        }
        error = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }
        do {
            async let overviewResponse: DashboardOverview = apiClient.dashboardOverview()
            async let patientsResponse: PriorityPatientListResponse = apiClient.priorityPatients(page: page, query: query.cvNilIfEmpty, riskLevel: selectedRiskLevel)
            let values: (DashboardOverview, PriorityPatientListResponse) = try await (overviewResponse, patientsResponse)
            overview = values.0
            patients = reset ? values.1.items : patients + values.1.items
            hasNext = values.1.hasNext
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current patient: PatientSummary) async {
        guard hasNext, !isLoadingMore, patient.id == patients.last?.id else { return }
        page += 1
        await load(reset: false)
    }
}

@MainActor
final class PatientDetailViewModel: ObservableObject {
    @Published var profile: PatientProfile?
    @Published var timeline: [TimelineEntry] = []
    @Published var isLoading = false
    @Published var error: APIError?
    @Published var noteText = ""
    @Published var editingEntry: TimelineEntry?

    let patientId: String
    private let apiClient: APIClient
    private var pollingTask: Task<Void, Never>?

    convenience init(patientId: String) {
        self.init(patientId: patientId, apiClient: .shared)
    }

    init(patientId: String, apiClient: APIClient) {
        self.patientId = patientId
        self.apiClient = apiClient
    }

    deinit {
        pollingTask?.cancel()
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let patientResponse: PatientResponse = apiClient.patient(id: patientId)
            async let timelineResponse: PatientTimelineResponse = apiClient.patientTimeline(patientId: patientId)
            let values: (PatientResponse, PatientTimelineResponse) = try await (patientResponse, timelineResponse)
            profile = values.0.patient
            timeline = values.1.items
            pollPendingEntriesIfNeeded()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func markViewed(_ entry: TimelineEntry) async {
        await update(entry, status: .viewed, note: nil)
    }

    func markCalledBack(_ entry: TimelineEntry) async {
        await update(entry, status: .calledBack, note: noteText.cvNilIfEmpty)
    }

    func saveNote() async {
        guard let editingEntry else { return }
        await update(editingEntry, status: editingEntry.handlingStatus ?? .viewed, note: noteText.cvNilIfEmpty)
        self.editingEntry = nil
        self.noteText = ""
    }

    private func update(_ entry: TimelineEntry, status: HandlingStatus, note: String?) async {
        do {
            _ = try await apiClient.updateHandling(patientId: patientId, entryId: entry.id, status: status, note: note)
            HapticsManager.success()
            await load()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    private func pollPendingEntriesIfNeeded() {
        let jobIds = timeline.compactMap { entry -> String? in
            guard entry.status == .analyzing || entry.status == .processing || entry.status == .transcribing else {
                return nil
            }
            return entry.jobId
        }
        guard !jobIds.isEmpty else { return }
        pollingTask?.cancel()
        let apiClient = apiClient
        pollingTask = Task { [weak self] in
            guard let self else { return }
            for jobId in jobIds {
                do {
                    _ = try await AsyncPoller<CheckinJobResponse>(configuration: PollingConfiguration(timeout: 60)).poll {
                        try await apiClient.checkinJob(id: jobId)
                    } isComplete: { response in
                        response.status == .completed || response.status == .failed
                    } isFailure: { response in
                        response.status == .failed
                    } serverDelay: { response in
                        response.pollAfterSeconds
                    }
                } catch {
                    continue
                }
            }
            await self.load()
        }
    }
}

@MainActor
final class NewPatientViewModel: ObservableObject {
    @Published var patientCode = ""
    @Published var fullName = ""
    @Published var phoneNumber = ""
    @Published var caregiverName = ""
    @Published var caregiverPhone = ""
    @Published var diagnosisText = ""
    @Published var notes = ""
    @Published var createdPatient: PatientProfile?
    @Published var isLoading = false
    @Published var error: APIError?

    private let apiClient: APIClient

    convenience init() {
        self.init(apiClient: .shared)
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    var canSubmit: Bool {
        !patientCode.cvTrimmed.isEmpty && !fullName.cvTrimmed.isEmpty && !phoneNumber.cvTrimmed.isEmpty
    }

    func submit() async {
        guard canSubmit else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let request = PatientCreateRequest(
                patientCode: patientCode.cvTrimmed,
                fullName: fullName.cvTrimmed,
                dateOfBirth: nil,
                gender: nil,
                phoneNumber: phoneNumber.cvTrimmed,
                caregiverName: caregiverName.cvNilIfEmpty,
                caregiverPhoneNumber: caregiverPhone.cvNilIfEmpty,
                diagnoses: diagnosisText.split(separator: ",").map { String($0).cvTrimmed }.filter { !$0.isEmpty },
                address: nil,
                primaryDoctorName: nil,
                notes: notes.cvNilIfEmpty
            )
            createdPatient = try await apiClient.createPatient(request).patient
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }
}

@MainActor
final class DocumentUploadViewModel: ObservableObject {
    @Published var selectedFileURL: URL?
    @Published var documentType: DocumentType = .prescription
    @Published var ocrMode: OcrMode = .auto
    @Published var uploadResponse: DocumentUploadResponse?
    @Published var isUploading = false
    @Published var error: APIError?

    let patientId: String
    private let apiClient: APIClient

    convenience init(patientId: String) {
        self.init(patientId: patientId, apiClient: .shared)
    }

    init(patientId: String, apiClient: APIClient) {
        self.patientId = patientId
        self.apiClient = apiClient
    }

    func upload() async {
        guard let selectedFileURL else { return }
        isUploading = true
        error = nil
        defer { isUploading = false }
        do {
            uploadResponse = try await apiClient.uploadDocument(patientId: patientId, documentType: documentType, mode: ocrMode, fileURL: selectedFileURL)
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }
}

@MainActor
final class OCRProcessingViewModel: ObservableObject {
    @Published var job: OCRJobResponse?
    @Published var isPolling = false
    @Published var error: APIError?

    let jobId: String
    private let apiClient: APIClient

    convenience init(jobId: String) {
        self.init(jobId: jobId, apiClient: .shared)
    }

    init(jobId: String, apiClient: APIClient) {
        self.jobId = jobId
        self.apiClient = apiClient
    }

    func startPolling() async {
        isPolling = true
        error = nil
        defer { isPolling = false }
        do {
            let apiClient = apiClient
            let jobId = jobId
            job = try await AsyncPoller<OCRJobResponse>(configuration: PollingConfiguration(timeout: 120)).poll {
                try await apiClient.ocrJob(id: jobId)
            } isComplete: { response in
                response.status == .needsReview || response.status == .completed || response.status == .failed
            } isFailure: { response in
                response.status == .failed || response.status == .cancelled
            } serverDelay: { response in
                response.pollAfterSeconds
            }
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func cancel() async {
        do {
            _ = try await apiClient.cancelOCRJob(id: jobId, reason: "user_cancelled")
            HapticsManager.warning()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }
}

@MainActor
final class OCRReviewViewModel: ObservableObject {
    @Published var medications: [OCRDraftMedication]
    @Published var followUp: FollowUpDraft?
    @Published var nurseNote = ""
    @Published var isSaving = false
    @Published var error: APIError?
    @Published var didSave = false

    private let patientId: String
    private let uploadId: String
    private let jobId: String
    private let apiClient: APIClient
    private let session: SessionManager

    convenience init(patientId: String, job: OCRJobResponse) {
        self.init(patientId: patientId, job: job, apiClient: .shared, session: .shared)
    }

    init(patientId: String, job: OCRJobResponse, apiClient: APIClient, session: SessionManager) {
        self.patientId = patientId
        self.uploadId = job.uploadId ?? ""
        self.jobId = job.jobId
        self.medications = job.draftMedications ?? []
        self.followUp = job.draftFollowUp
        self.apiClient = apiClient
        self.session = session
    }

    func addMedication() {
        medications.append(OCRDraftMedication(name: "", strength: nil, dosage: nil, frequency: nil, timesOfDay: nil, instructions: nil, confidence: nil))
    }

    func removeMedication(at offsets: IndexSet) {
        medications.remove(atOffsets: offsets)
    }

    func confirm() async {
        guard !uploadId.isEmpty else {
            error = .file(message: L10n.text("staff.ocr.missing_upload"))
            return
        }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let confirmed = medications
                .filter { !$0.name.cvTrimmed.isEmpty }
                .map {
                    Medication(
                        id: nil,
                        name: $0.name.cvTrimmed,
                        strength: $0.strength?.cvNilIfEmpty,
                        dosage: $0.dosage?.cvNilIfEmpty,
                        frequency: $0.frequency?.cvNilIfEmpty,
                        timesOfDay: $0.timesOfDay,
                        instructions: $0.instructions?.cvNilIfEmpty,
                        startDate: nil,
                        endDate: nil,
                        isActive: true
                    )
                }
            let request = OCRConfirmRequest(
                jobId: jobId,
                confirmedByUserId: session.currentUser?.id,
                medications: confirmed,
                followUp: followUp,
                nurseNote: nurseNote.cvNilIfEmpty
            )
            _ = try await apiClient.confirmOCR(patientId: patientId, uploadId: uploadId, request: request)
            didSave = true
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }
}
