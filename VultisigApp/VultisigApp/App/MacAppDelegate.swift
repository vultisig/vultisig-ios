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

        // The toolbar background is forced dark (see VultisigApp.swift), so the
        // title text needs to be forced to the dark-appearance's white to stay
        // readable when the system is in light mode.
        NSApp.appearance = NSAppearance(named: .darkAqua)
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
