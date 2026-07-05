import SwiftUI

@available(iOS 16.0, *)
@main
struct CareVoiceAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var reachability = ReachabilityMonitor.shared
    @StateObject private var notificationManager = NotificationManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionManager)
                .environmentObject(reachability)
                .environmentObject(notificationManager)
                .onAppear {
                    reachability.start()
                    Task {
                        await sessionManager.restoreSession()
                    }
                }
        }
    }
}
