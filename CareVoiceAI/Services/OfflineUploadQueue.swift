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
    let duration: TimeInterval?
    let createdAt: Date
    var retryCount: Int
}

actor OfflineUploadQueue {
    static let shared = OfflineUploadQueue()

    private let manifestURL = FileStorage.offlineQueueDirectory.appendingPathComponent("manifest.json")
    private let apiClient = APIClient.shared

    func enqueueCheckin(checkinId: String, audioURL: URL?, quickAnswerId: String?, duration: TimeInterval?) async throws {
        let storedFileName: String
        if let audioURL {
            storedFileName = "\(UUID().uuidString)-\(audioURL.lastPathComponent)"
            let destination = FileStorage.offlineQueueDirectory.appendingPathComponent(storedFileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: audioURL, to: destination)
        } else {
            storedFileName = ""
        }
        var items = load()
        items.append(OfflineUploadItem(
            id: UUID().uuidString,
            kind: .checkinResponse,
            patientId: nil,
            checkinId: checkinId,
            audioFileName: storedFileName,
            quickAnswerId: quickAnswerId,
            duration: duration,
            createdAt: Date(),
            retryCount: 0
        ))
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
                    guard let checkinId = item.checkinId else { continue }
                    let audioURL = item.audioFileName.isEmpty ? nil : FileStorage.offlineQueueDirectory.appendingPathComponent(item.audioFileName)
                    _ = try await apiClient.submitCheckin(
                        checkinId: checkinId,
                        audioURL: audioURL,
                        quickAnswerId: item.quickAnswerId,
                        duration: item.duration
                    )
                    if !item.audioFileName.isEmpty {
                        try? FileManager.default.removeItem(at: FileStorage.offlineQueueDirectory.appendingPathComponent(item.audioFileName))
                    }
                case .hotlineVoice:
                    remaining.append(item)
                }
            } catch {
                item.retryCount += 1
                remaining.append(item)
            }
        }
        save(remaining)
    }

    func pendingCount() -> Int {
        load().count
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
