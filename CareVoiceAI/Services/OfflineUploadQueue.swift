import Foundation

enum OfflineUploadKind: String, Codable {
    case checkinResponse
    case hotlineVoice
}

struct OfflineUploadItem: Codable, Identifiable {
    let id: String
    let kind: OfflineUploadKind
    let patientId: String?
    let checkinId: String?
    let audioFileName: String
    let quickAnswerId: String?
    let confirmedTranscript: String?
    let patientDeclaredRiskLevel: String?
    let duration: TimeInterval?
    let clientRequestId: String
    let createdAt: Date
    var retryCount: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, patientId, checkinId, audioFileName, quickAnswerId, confirmedTranscript
        case patientDeclaredRiskLevel, duration, clientRequestId, createdAt, retryCount
    }

    init(
        id: String,
        kind: OfflineUploadKind,
        patientId: String?,
        checkinId: String?,
        audioFileName: String,
        quickAnswerId: String?,
        confirmedTranscript: String?,
        patientDeclaredRiskLevel: String?,
        duration: TimeInterval?,
        clientRequestId: String,
        createdAt: Date,
        retryCount: Int
    ) {
        self.id = id
        self.kind = kind
        self.patientId = patientId
        self.checkinId = checkinId
        self.audioFileName = audioFileName
        self.quickAnswerId = quickAnswerId
        self.confirmedTranscript = confirmedTranscript
        self.patientDeclaredRiskLevel = patientDeclaredRiskLevel
        self.duration = duration
        self.clientRequestId = clientRequestId
        self.createdAt = createdAt
        self.retryCount = retryCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(OfflineUploadKind.self, forKey: .kind)
        patientId = try container.decodeIfPresent(String.self, forKey: .patientId)
        checkinId = try container.decodeIfPresent(String.self, forKey: .checkinId)
        audioFileName = try container.decode(String.self, forKey: .audioFileName)
        quickAnswerId = try container.decodeIfPresent(String.self, forKey: .quickAnswerId)
        confirmedTranscript = try container.decodeIfPresent(String.self, forKey: .confirmedTranscript)
        patientDeclaredRiskLevel = try container.decodeIfPresent(String.self, forKey: .patientDeclaredRiskLevel)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        clientRequestId = try container.decodeIfPresent(String.self, forKey: .clientRequestId) ?? UUID().uuidString
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        retryCount = try container.decode(Int.self, forKey: .retryCount)
    }
}

actor OfflineUploadQueue {
    static let shared = OfflineUploadQueue()

    private let manifestURL = FileStorage.offlineQueueDirectory.appendingPathComponent("manifest.json")
    private let apiClient = APIClient.shared
    private let maxRetries = 12

    func enqueueCheckin(
        checkinId: String,
        audioURL: URL?,
        quickAnswerId: String?,
        confirmedTranscript: String?,
        patientDeclaredRiskLevel: RiskLevel?,
        duration: TimeInterval?
    ) async throws {
        let clientRequestId = UUID().uuidString
        let storedFileName = try storeAudioIfNeeded(audioURL)
        var items = load()
        items.append(
            OfflineUploadItem(
                id: UUID().uuidString,
                kind: .checkinResponse,
                patientId: nil,
                checkinId: checkinId,
                audioFileName: storedFileName,
                quickAnswerId: quickAnswerId,
                confirmedTranscript: confirmedTranscript?.cvNilIfEmpty,
                patientDeclaredRiskLevel: patientDeclaredRiskLevel?.rawValue,
                duration: duration,
                clientRequestId: clientRequestId,
                createdAt: Date(),
                retryCount: 0
            )
        )
        save(items)
    }

    func enqueueHotlineVoice(patientId: String?, audioURL: URL, duration: TimeInterval?) async throws {
        let clientRequestId = UUID().uuidString
        let storedFileName = try storeAudioIfNeeded(audioURL)
        guard !storedFileName.isEmpty else {
            throw APIError.file(message: L10n.text("error.file_unreadable"))
        }
        var items = load()
        items.append(
            OfflineUploadItem(
                id: UUID().uuidString,
                kind: .hotlineVoice,
                patientId: patientId,
                checkinId: nil,
                audioFileName: storedFileName,
                quickAnswerId: nil,
                confirmedTranscript: nil,
                patientDeclaredRiskLevel: nil,
                duration: duration,
                clientRequestId: clientRequestId,
                createdAt: Date(),
                retryCount: 0
            )
        )
        save(items)
    }

    func retryPendingUploads() async {
        let items = load()
        guard !items.isEmpty else { return }

        var remaining: [OfflineUploadItem] = []
        for var item in items {
            do {
                switch item.kind {
                case .checkinResponse:
                    try await uploadCheckin(item)
                case .hotlineVoice:
                    try await uploadHotlineVoice(item)
                }
                removeStoredAudio(named: item.audioFileName)
            } catch {
                item.retryCount += 1
                if item.retryCount <= maxRetries {
                    remaining.append(item)
                } else {
                    removeStoredAudio(named: item.audioFileName)
                }
            }
        }
        save(remaining)
    }

    func pendingCount() -> Int {
        load().count
    }

    private func uploadCheckin(_ item: OfflineUploadItem) async throws {
        guard let checkinId = item.checkinId else { return }
        let audioURL = item.audioFileName.isEmpty
            ? nil
            : FileStorage.offlineQueueDirectory.appendingPathComponent(item.audioFileName)
        let declaredLevel = item.patientDeclaredRiskLevel.flatMap { RiskLevel(rawValue: $0) }
        _ = try await apiClient.submitCheckin(
            checkinId: checkinId,
            audioURL: audioURL,
            quickAnswerId: item.quickAnswerId,
            confirmedTranscript: item.confirmedTranscript,
            patientDeclaredRiskLevel: declaredLevel,
            duration: item.duration,
            clientRequestId: item.clientRequestId
        )
    }

    private func uploadHotlineVoice(_ item: OfflineUploadItem) async throws {
        let audioURL = FileStorage.offlineQueueDirectory.appendingPathComponent(item.audioFileName)
        let audioData = try Data(contentsOf: audioURL)
        var clientRequestId = item.clientRequestId
        for attempt in 0..<2 {
            do {
                _ = try await apiClient.askHotlineVoice(
                    patientId: item.patientId,
                    audioData: audioData,
                    fileName: item.audioFileName,
                    mimeType: audioURL.uploadMimeType,
                    duration: item.duration,
                    clientRequestId: clientRequestId
                )
                return
            } catch let error as APIError {
                if case .server(let code, _, let statusCode, _) = error,
                   code == "conflict", statusCode == 409, attempt == 0 {
                    clientRequestId = UUID().uuidString
                    continue
                }
                throw error
            }
        }
    }

    private func storeAudioIfNeeded(_ audioURL: URL?) throws -> String {
        guard let audioURL else { return "" }
        let storedFileName = "\(UUID().uuidString)-\(audioURL.lastPathComponent)"
        let destination = FileStorage.offlineQueueDirectory.appendingPathComponent(storedFileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: audioURL, to: destination)
        return storedFileName
    }

    private func removeStoredAudio(named fileName: String) {
        guard !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: FileStorage.offlineQueueDirectory.appendingPathComponent(fileName))
    }

    private func load() -> [OfflineUploadItem] {
        guard let data = try? Data(contentsOf: manifestURL) else {
            return []
        }
        return (try? DateFormatters.apiDecoder.decode([OfflineUploadItem].self, from: data)) ?? []
    }

    private func save(_ items: [OfflineUploadItem]) {
        guard let data = try? DateFormatters.apiEncoder.encode(items) else {
            return
        }
        try? data.write(to: manifestURL, options: .atomic)
    }
}