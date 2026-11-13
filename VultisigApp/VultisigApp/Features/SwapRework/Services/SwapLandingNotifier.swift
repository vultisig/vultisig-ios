//
//  SwapLandingNotifier.swift
//  VultisigApp
//
//  "Notify me" on the swap tracker (R4 1_11 / 1_12). Permission goes through
//  the app's existing `PushNotificationManager`; the notification itself is
//  local, fired from the done screen's status poller when the swap completes.
//  A push after the app is closed needs a backend hook and is not built: the
//  card says the alert comes while Vultisig is running.
//

import Foundation
import OSLog
import UserNotifications

private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-landing-notifier")

@MainActor
@Observable
final class SwapLandingNotifier {
    enum State: Equatable {
        case off
        case on
        /// The OS permission is off: the card links to notification settings.
        case permissionDenied
    }

    private(set) var state: State
    @ObservationIgnored private var didFire = false

    init(state: State = .off) {
        self.state = state
    }

    func turnOn() async {
        let manager = PushNotificationManager.shared
        switch await manager.authorizationStatus() {
        case .notDetermined:
            state = await manager.requestPermission() ? .on : .permissionDenied
        case .denied:
            state = .permissionDenied
        default:
            state = .on
        }
    }

    func turnOff() {
        state = .off
    }

    /// Once per swap, only when the user asked for it.
    func swapCompleted(title: String, body: String) {
        guard state == .on, !didFire else { return }
        didFire = true
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "swap-landed-\(UUID().uuidString)", content: content, trigger: nil)
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                logger.error("Swap landed notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
