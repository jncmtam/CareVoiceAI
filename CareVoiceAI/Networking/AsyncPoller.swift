import Foundation

struct PollingConfiguration {
    var timeout: TimeInterval = 90
    var initialDelay: TimeInterval = 1
    var maxDelay: TimeInterval = 8
    var backoffMultiplier: Double = 1.35
}

struct AsyncPoller<Response> {
    let configuration: PollingConfiguration

    init(configuration: PollingConfiguration = PollingConfiguration()) {
        self.configuration = configuration
    }

    func poll(
        operation: @escaping () async throws -> Response,
        isComplete: @escaping (Response) -> Bool,
        isFailure: @escaping (Response) -> Bool,
        serverDelay: @escaping (Response) -> TimeInterval?
    ) async throws -> Response {
        let startedAt = Date()
        var delay = configuration.initialDelay

        while true {
            try Task.checkCancellation()
            let response = try await operation()

            if isComplete(response) {
                return response
            }
            if isFailure(response) {
                return response
            }
            if Date().timeIntervalSince(startedAt) > configuration.timeout {
                throw APIError.pollingTimeout
            }

            let requestedDelay = serverDelay(response)
            let jitteredDelay = delay * Double.random(in: 0.85...1.15)
            let sleepSeconds = min(requestedDelay ?? jitteredDelay, configuration.maxDelay)
            try await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
            delay = min(delay * configuration.backoffMultiplier, configuration.maxDelay)
        }
    }
}
