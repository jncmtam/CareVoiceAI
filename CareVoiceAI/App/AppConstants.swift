import Foundation

nonisolated enum AppConstants {
    static let bundleIdentifier = "com.carevoice.ai"
    static let defaultBaseURL = "http://127.0.0.1:8000/api/v1"
    static let selectedRoleKey = "selected_role"
    static let apiBaseURLKey = "api_base_url"
    static let demoModeKey = "demo_mode_enabled"
    static let deviceIDKey = "device_id"

    static var isDemoMode: Bool {
        get {
            if UserDefaults.standard.object(forKey: demoModeKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: demoModeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: demoModeKey)
        }
    }
}
