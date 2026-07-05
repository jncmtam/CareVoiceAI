import Foundation

actor TokenRefreshCoordinator {
    static let shared = TokenRefreshCoordinator()

    private var refreshTask: Task<Void, Error>?

    func refresh(using tokenStore: TokenStore, exchange: @escaping () async throws -> RefreshTokenResponse) async throws {
        if let refreshTask {
            try await refreshTask.value
            return
        }

        let task = Task<Void, Error> {
            guard tokenStore.refreshToken != nil else {
                throw APIError.missingToken
            }
            let response = try await exchange()
            tokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }
}
