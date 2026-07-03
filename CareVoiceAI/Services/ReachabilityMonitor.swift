import Foundation
import Network

@MainActor
final class ReachabilityMonitor: ObservableObject {
    static let shared = ReachabilityMonitor()

    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "CareVoiceAI.Reachability")
    private var didStart = false

    private init() {}

    func start() {
        guard !didStart else { return }
        didStart = true
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = isConnected
                if isConnected {
                    Task {
                        await OfflineUploadQueue.shared.retryPendingUploads()
                    }
                }
            }
        }
        monitor.start(queue: queue)
    }
}
