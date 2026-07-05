import Foundation

enum StaffOverviewFilter: Equatable {
    case all
    case attention
    case intervention
}

@MainActor
final class StaffDashboardViewModel: ObservableObject {
    @Published var overview: DashboardOverview?
    @Published var patients: [PatientSummary] = []
    @Published var selectedRiskLevel: RiskLevel?
    @Published var selectedOverviewFilter: StaffOverviewFilter?
    @Published var filterActionableOnly = false
    @Published var shouldScrollToPatientList = false
    @Published var query = ""
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasNext = false
    @Published var error: APIError?
    @Published var showCriticalBanner = false
    @Published var didTriggerCriticalHaptic = false

    var displayedPatients: [PatientSummary] {
        Self.sortPatientsByPriority(patients)
    }

    var topCriticalPatient: PatientSummary? {
        displayedPatients
            .filter(Self.isActionableCritical)
            .first
    }

    private let apiClient: APIClient
    private var page = 1
    private var lastAlertSignature: String?
    private var didPrimeAlertBaseline = false
    private var refreshTimer: Timer?
    private(set) var suppressRiskPickerReload = false

    convenience init() {
        self.init(apiClient: .shared)
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.load()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func load(reset: Bool = true, notifyOnNewAlerts: Bool = true) async {
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
            async let patientsResponse: PriorityPatientListResponse = apiClient.priorityPatients(
                page: page,
                query: query.cvNilIfEmpty,
                riskLevel: selectedRiskLevel,
                actionableOnly: filterActionableOnly
            )
            let values: (DashboardOverview, PriorityPatientListResponse) = try await (overviewResponse, patientsResponse)
            overview = values.0
            let merged = reset ? values.1.items : patients + values.1.items
            patients = Self.sortPatientsByPriority(merged)
            hasNext = values.1.hasNext
            await notifyIfCriticalAlertsIncreased(notifyOnNewAlerts: notifyOnNewAlerts)
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func selectOverviewFilter(_ filter: StaffOverviewFilter) async {
        suppressRiskPickerReload = true
        defer { suppressRiskPickerReload = false }

        if selectedOverviewFilter == filter {
            clearOverviewFilter()
            await load(notifyOnNewAlerts: false)
            return
        }

        selectedOverviewFilter = filter
        switch filter {
        case .all:
            selectedRiskLevel = nil
            filterActionableOnly = false
        case .attention:
            selectedRiskLevel = .attention
            filterActionableOnly = true
        case .intervention:
            selectedRiskLevel = .intervention
            filterActionableOnly = true
        }
        shouldScrollToPatientList = true
        await load(notifyOnNewAlerts: false)
    }

    func syncOverviewFilterFromRiskPicker() {
        switch selectedRiskLevel {
        case .attention:
            selectedOverviewFilter = .attention
            filterActionableOnly = true
        case .intervention:
            selectedOverviewFilter = .intervention
            filterActionableOnly = true
        case .normal, .none:
            selectedOverviewFilter = nil
            filterActionableOnly = false
        }
    }

    private func clearOverviewFilter() {
        selectedOverviewFilter = nil
        selectedRiskLevel = nil
        filterActionableOnly = false
    }

    static func isActionable(_ patient: PatientSummary) -> Bool {
        guard let status = patient.handlingStatus else { return false }
        return status == .new || status == .viewed || status == .calledBack
    }

    private static func isActionableCritical(_ patient: PatientSummary) -> Bool {
        guard let risk = patient.latestRiskLevel, risk == .intervention || risk == .attention else {
            return false
        }
        return isActionable(patient)
    }

    static func sortPatientsByPriority(_ patients: [PatientSummary]) -> [PatientSummary] {
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

    private func notifyIfCriticalAlertsIncreased(notifyOnNewAlerts: Bool) async {
        guard notifyOnNewAlerts, let critical = topCriticalPatient else { return }

        let signature = alertSignature(for: critical)
        if !didPrimeAlertBaseline {
            didPrimeAlertBaseline = true
            lastAlertSignature = signature
            return
        }
        guard signature != lastAlertSignature else { return }
        lastAlertSignature = signature

        HapticsManager.critical()
        HapticsManager.playStaffCriticalAlertSound()
        didTriggerCriticalHaptic = true
        showCriticalBanner = true
        NotificationManager.shared.scheduleCriticalStaffAlert(
            count: 1,
            patientId: critical.patientId,
            patientName: critical.fullName
        )
    }

    private func alertSignature(for patient: PatientSummary) -> String {
        [
            patient.patientId,
            patient.latestRiskLevel?.rawValue,
            patient.handlingStatus?.rawValue,
            patient.latestCheckinAt.map { String($0.timeIntervalSince1970) }
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    func loadMoreIfNeeded(current patient: PatientSummary) async {
        guard hasNext, !isLoadingMore, patient.id == patients.last?.id else { return }
        page += 1
        await load(reset: false)
    }

    func deletePatient(_ patient: PatientSummary) async -> Bool {
        error = nil
        do {
            _ = try await apiClient.deletePatient(id: patient.patientId)
            patients.removeAll { $0.patientId == patient.patientId }
            HapticsManager.success()
            await load()
            return true
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
            return false
        }
    }
}

@MainActor
final class StaffNotificationsViewModel: ObservableObject {
    @Published var items: [StaffNotificationItem] = []
    @Published var unreadCount = 0
    @Published var isLoading = false
    @Published var hasNext = false
    @Published var error: APIError?

    private let apiClient: APIClient
    private var page = 1
    private var lastSignature: String?
    private var didPrimeBaseline = false
    private var refreshTimer: Timer?

    convenience init() {
        self.init(apiClient: .shared)
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.load(notifyOnNew: true)
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func load(reset: Bool = true, notifyOnNew: Bool = false) async {
        if reset {
            page = 1
            isLoading = true
        }
        error = nil
        defer { isLoading = false }
        do {
            let response = try await apiClient.staffNotifications(page: page)
            items = reset ? response.items : items + response.items
            unreadCount = response.unreadCount
            hasNext = response.hasNext
            if notifyOnNew {
                notifyIfNewRiskChanges(in: response.items)
            }
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func markRead(_ item: StaffNotificationItem) async {
        guard item.unread else { return }
        do {
            _ = try await apiClient.markStaffNotificationRead(id: item.id)
            await load(notifyOnNew: false)
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func markAllRead() async {
        do {
            try await apiClient.markAllStaffNotificationsRead()
            unreadCount = 0
            await load()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    private func notifyIfNewRiskChanges(in latest: [StaffNotificationItem]) {
        let unreadItems = latest.filter(\.unread)
        guard let newest = unreadItems.first else { return }
        let signature = newest.id
        if !didPrimeBaseline {
            didPrimeBaseline = true
            lastSignature = signature
            return
        }
        guard signature != lastSignature else { return }
        lastSignature = signature
        HapticsManager.critical()
        HapticsManager.playStaffCriticalAlertSound()
        NotificationManager.shared.scheduleStaffRiskChangeNotification(
            patientName: newest.patientName,
            patientId: newest.patientId,
            message: newest.message
        )
    }
}

@MainActor
final class PatientDetailViewModel: ObservableObject {
    @Published var profile: PatientProfile?
    @Published var medications: [Medication] = []
    @Published var appointments: [Appointment] = []
    @Published var timelineHeader: TimelinePatientHeader?
    @Published var timeline: [TimelineEntry] = []
    @Published var isLoading = false
    @Published var error: APIError?
    @Published var noteText = ""
    @Published var editingEntry: TimelineEntry?
    @Published var isEditingProfile = false
    @Published var isSavingProfile = false
    @Published var profileSavedMessage: String?
    @Published var editFullName = ""
    @Published var editCaregiverName = ""
    @Published var editPhone = ""
    @Published var editCaregiverPhone = ""
    @Published var editNotes = ""

    let patientId: String
    private let apiClient: APIClient
    private var pollingTask: Task<Void, Never>?
    private var completedJobIds: Set<String> = []

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
            async let medicationsResponse: MedicationListResponse = apiClient.medications(patientId: patientId)
            async let appointmentsResponse: AppointmentListResponse = apiClient.appointments(patientId: patientId)
            async let timelineResponse: PatientTimelineResponse = apiClient.patientTimeline(patientId: patientId)
            let values: (PatientResponse, MedicationListResponse, AppointmentListResponse, PatientTimelineResponse) = try await (
                patientResponse,
                medicationsResponse,
                appointmentsResponse,
                timelineResponse
            )
            profile = values.0.patient
            medications = values.1.medications
            appointments = values.2.appointments
            timelineHeader = values.3.patient
            timeline = values.3.items
            pollPendingEntriesIfNeeded()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func markViewed(_ entry: TimelineEntry) async {
        await update(entry, status: .viewed, note: nil)
    }

    func markResolved(_ entry: TimelineEntry) async {
        await update(entry, status: .resolved, note: entry.staffNote)
    }

    func markCalledBack(_ entry: TimelineEntry) async {
        await update(entry, status: .calledBack, note: entry.staffNote, callbackAt: Date())
    }

    func beginNoteEditing(for entry: TimelineEntry) {
        editingEntry = entry
        noteText = entry.staffNote ?? ""
    }

    func saveNote() async {
        guard let editingEntry else { return }
        let current = editingEntry.handlingStatus ?? .new
        let nextStatus: HandlingStatus = current == .new ? .viewed : current
        await update(editingEntry, status: nextStatus, note: noteText.cvNilIfEmpty)
        self.editingEntry = nil
        self.noteText = ""
    }

    func beginProfileEditing() {
        editFullName = profile?.fullName ?? ""
        editCaregiverName = profile?.caregiverName ?? ""
        editPhone = profile?.phoneNumber ?? ""
        editCaregiverPhone = profile?.caregiverPhoneNumber ?? ""
        editNotes = profile?.notes ?? ""
        profileSavedMessage = nil
        isEditingProfile = true
    }

    func saveProfile() async {
        isSavingProfile = true
        error = nil
        profileSavedMessage = nil
        defer { isSavingProfile = false }
        do {
            let request = PatientUpdateRequest(
                fullName: editFullName.cvNilIfEmpty,
                phoneNumber: editPhone.cvNilIfEmpty,
                caregiverName: editCaregiverName.cvNilIfEmpty,
                caregiverPhoneNumber: editCaregiverPhone.cvNilIfEmpty,
                notes: editNotes.cvNilIfEmpty
            )
            let response = try await apiClient.updatePatient(id: patientId, request: request)
            profile = response.patient
            profileSavedMessage = L10n.text("staff.edit_patient.saved")
            isEditingProfile = false
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    private func update(_ entry: TimelineEntry, status: HandlingStatus, note: String?, callbackAt: Date? = nil) async {
        do {
            _ = try await apiClient.updateHandling(
                patientId: patientId,
                entryId: entry.id,
                status: status,
                note: note,
                callbackAt: callbackAt
            )
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
            guard let jobId = entry.jobId, !completedJobIds.contains(jobId) else {
                return nil
            }
            return jobId
        }
        guard !jobIds.isEmpty else { return }
        pollingTask?.cancel()
        let apiClient = apiClient
        pollingTask = Task { [weak self] in
            guard let self else { return }
            for jobId in jobIds {
                do {
                    let result = try await AsyncPoller<CheckinJobResponse>(configuration: PollingConfiguration(timeout: 60)).poll {
                        try await apiClient.checkinJob(id: jobId)
                    } isComplete: { response in
                        response.status == .completed || response.status == .failed
                    } isFailure: { response in
                        response.status == .failed
                    } serverDelay: { response in
                        response.pollAfterSeconds
                    }
                    if result.status == .completed || result.status == .failed {
                        self.completedJobIds.insert(jobId)
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
    @Published var fullName = ""
    @Published var phoneNumber = ""
    @Published var caregiverName = ""
    @Published var caregiverPhone = ""
    @Published var diagnosisText = ""
    @Published var notes = ""
    @Published var createdPatient: PatientProfile?
    @Published var successMessage: String?
    @Published var fieldErrors: [PatientInputValidator.Field: String] = [:]
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
        !fullName.cvTrimmed.isEmpty && !phoneNumber.cvTrimmed.isEmpty && !isLoading
    }

    func validateLocally() -> Bool {
        let result = PatientInputValidator.validateNewPatient(
            fullName: fullName,
            phoneNumber: phoneNumber,
            caregiverPhone: caregiverPhone
        )
        fieldErrors = result.fieldErrors
        return result.isValid
    }

    func submit() async {
        guard canSubmit, !isLoading else { return }
        guard validateLocally() else { return }

        isLoading = true
        error = nil
        successMessage = nil
        defer { isLoading = false }

        do {
            let request = PatientCreateRequest(
                fullName: fullName.cvTrimmed,
                dateOfBirth: nil,
                gender: nil,
                phoneNumber: PatientInputValidator.normalizePhoneNumber(phoneNumber),
                caregiverName: caregiverName.cvNilIfEmpty,
                caregiverPhoneNumber: caregiverPhone.cvTrimmed.isEmpty
                    ? nil
                    : PatientInputValidator.normalizePhoneNumber(caregiverPhone),
                diagnoses: diagnosisText.split(separator: ",").map { String($0).cvTrimmed }.filter { !$0.isEmpty },
                address: nil,
                primaryDoctorName: nil,
                notes: notes.cvNilIfEmpty
            )
            let patient = try await apiClient.createPatient(request).patient
            createdPatient = patient
            successMessage = String(format: L10n.text("staff.new_patient.success"), patient.fullName, patient.patientCode)
            resetForm(keepingCreatedPatient: patient)
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    private func resetForm(keepingCreatedPatient patient: PatientProfile) {
        fullName = ""
        phoneNumber = ""
        caregiverName = ""
        caregiverPhone = ""
        diagnosisText = ""
        notes = ""
        fieldErrors = [:]
        createdPatient = patient
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
                response.status == .needsReview || response.status == .completed || response.status == .failed || response.status == .cancelled
            } isFailure: { _ in
                false
            } serverDelay: { response in
                response.pollAfterSeconds
            }
            if job?.status == .failed || job?.status == .cancelled {
                self.error = APIError.server(
                    code: job?.errorCode ?? "job_failed",
                    message: job?.displayMessage ?? job?.errorMessage ?? L10n.text("staff.ocr.failed"),
                    statusCode: 503,
                    traceId: nil
                )
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
    @Published var patientFullName = ""
    @Published var patientPhone = ""
    @Published var patientDiagnoses = ""
    @Published var patientAddress = ""
    @Published var examiningDoctor = ""
    @Published var followUpDate = Date()
    @Published var hasFollowUpDate = false
    @Published var followUpDepartment = ""
    @Published var followUpDoctor = ""
    @Published var instructions = ""
    @Published var nurseNote = ""
    @Published var rawText = ""
    @Published var warnings: [String] = []
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
        self.rawText = job.rawText ?? ""
        self.warnings = job.warnings ?? []
        self.instructions = job.instructions ?? ""

        let patient = job.draftPatient
        self.patientFullName = patient?.fullName ?? ""
        self.patientPhone = patient?.phoneNumber ?? ""
        self.patientDiagnoses = patient?.diagnoses?.joined(separator: ", ") ?? ""
        self.patientAddress = patient?.address ?? ""
        self.examiningDoctor = patient?.primaryDoctorName ?? job.draftFollowUp?.doctorName ?? ""

        if let followUp = job.draftFollowUp {
            if let appointmentAt = followUp.appointmentAt {
                followUpDate = appointmentAt
                hasFollowUpDate = true
            }
            followUpDepartment = followUp.department ?? ""
            followUpDoctor = followUp.doctorName ?? ""
        }

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
            let diagnoses = patientDiagnoses
                .split(separator: ",")
                .map { String($0).cvTrimmed }
                .filter { !$0.isEmpty }
            let patientDraft = OCRPatientDraft(
                fullName: patientFullName.cvNilIfEmpty,
                phoneNumber: patientPhone.cvNilIfEmpty,
                dateOfBirth: nil,
                diagnoses: diagnoses.isEmpty ? nil : diagnoses,
                address: patientAddress.cvNilIfEmpty,
                primaryDoctorName: examiningDoctor.cvNilIfEmpty,
                confidence: nil
            )
            let followUpDoctorName = followUpDoctor.cvTrimmed.isEmpty ? examiningDoctor.cvTrimmed : followUpDoctor.cvTrimmed
            let followUp = hasFollowUpDate
                ? FollowUpDraft(
                    appointmentAt: followUpDate,
                    department: followUpDepartment.cvNilIfEmpty,
                    doctorName: followUpDoctorName.cvNilIfEmpty
                )
                : nil
            let request = OCRConfirmRequest(
                jobId: jobId,
                confirmedByUserId: session.currentUser?.id,
                medications: confirmed,
                followUp: followUp,
                patientDraft: patientDraft,
                instructions: instructions.cvNilIfEmpty,
                nurseNote: nurseNote.cvNilIfEmpty
            )
            _ = try await apiClient.confirmOCR(patientId: patientId, uploadId: uploadId, request: request)
            didSave = true
            NotificationCenter.default.post(name: .patientDataUpdated, object: patientId)
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }
}
