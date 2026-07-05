import Foundation

extension Notification.Name {
    static let patientDataUpdated = Notification.Name("carevoice.patientDataUpdated")
}

nonisolated enum AppConstants {
    static let bundleIdentifier = "com.carevoice.ai"
    static let defaultBaseURL = "http://127.0.0.1:8000/api/v1"
    static let selectedRoleKey = "selected_role"
    static let apiBaseURLKey = "api_base_url"
    static let deviceIDKey = "device_id"

    static var apiBaseURL: String {
        get {
            let saved = UserDefaults.standard.string(forKey: apiBaseURLKey)
            let bundled = Bundle.main.object(forInfoDictionaryKey: "CAREVOICE_API_BASE_URL") as? String
            #if targetEnvironment(simulator)
            return saved ?? bundled ?? defaultBaseURL
            #else
            if let saved, !isLoopbackAPIURL(saved) {
                return saved
            }
            return bundled ?? defaultBaseURL
            #endif
        }
        set {
            UserDefaults.standard.set(newValue, forKey: apiBaseURLKey)
        }
    }

    private static func isLoopbackAPIURL(_ raw: String) -> Bool {
        guard let host = URL(string: raw)?.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}
