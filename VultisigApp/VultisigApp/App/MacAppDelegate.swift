//
//  AppDelegate.swift
//  VultisigApp
//

#if os(macOS)
import AppKit
import OSLog

class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        PushNotificationManager.shared.setupNotificationDelegate()
    }

    func application(
        _: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.setDeviceToken(deviceToken)
        }
    }

    func application(
        _: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Log.app.other.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }
}
#endif
