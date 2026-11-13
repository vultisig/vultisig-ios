//
//  SwapLandingNotifier.swift
//  VultisigApp
//
//  "Notify me" on the swap tracker (R4 1_11 / 1_12). Permission goes through
//  the app's existing `PushNotificationManager`. Once on, the swap is handed to
//  the app-scoped `SwapLandingWatcher`, which keeps its own status poller after
//  the tracker is left ("Back to vault") and posts a local notification when
//  the swap completes. A push after the app is closed needs a backend hook and
//  is not built: the card says the alert comes while Vultisig is running.
//
//  The notification states no amount and no destination: it is posted on the
//  poller's completion, before the delivered amount is read.
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
    @ObservationIgnored private let hash: String
    @ObservationIgnored private let watcher: SwapLandingWatcher

    init(hash: String, watcher: SwapLandingWatcher? = nil) {
        // Resolved here, on the main actor, not as a default argument.
        let watcher = watcher ?? .shared
        self.hash = hash
        self.watcher = watcher
        self.state = watcher.isWatching(hash: hash) ? .on : .off
    }

    /// Asks for permission if needed, then hands the swap to the watcher with
    /// a fresh poller made for it.
    func turnOn(makeService: () -> DoneStatusService, title: String, body: String) async {
        let manager = PushNotificationManager.shared
        let granted: Bool
        switch await manager.authorizationStatus() {
        case .notDetermined:
            granted = await manager.requestPermission()
        case .denied:
            granted = false
        default:
            granted = true
        }
        guard granted else {
            state = .permissionDenied
            return
        }
        watcher.watch(hash: hash, service: makeService(), title: title, body: body)
        state = .on
    }

    func turnOff() {
        watcher.cancel(hash: hash)
        state = .off
    }
}

/// Keeps opted-in swaps' pollers alive for as long as the app runs, and posts
/// one notification per swap on completion. A failed swap ends the watch
/// without a notification (the tracker shows the failure).
@MainActor
final class SwapLandingWatcher {
    static let shared = SwapLandingWatcher()

    private struct Watch {
        let service: DoneStatusService
        let task: Task<Void, Never>
    }

    private var watches: [String: Watch] = [:]

    func isWatching(hash: String) -> Bool {
        watches[hash] != nil
    }

    func watch(hash: String, service: DoneStatusService, title: String, body: String) {
        guard watches[hash] == nil else { return }
        service.start()
        let task = Task { [weak self] in
            for await status in service.$status.values {
                switch status {
                case .confirmed:
                    await Self.post(title: title, body: body)
                    self?.cancel(hash: hash)
                    return
                case .failed:
                    self?.cancel(hash: hash)
                    return
                case .broadcasted, .pending, .timeout:
                    continue
                }
            }
        }
        watches[hash] = Watch(service: service, task: task)
    }

    func cancel(hash: String) {
        guard let watch = watches.removeValue(forKey: hash) else { return }
        watch.task.cancel()
        watch.service.stop()
    }

    private static func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "swap-landed-\(UUID().uuidString)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("Swap landed notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
