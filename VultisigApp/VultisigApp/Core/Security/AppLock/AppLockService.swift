//
//  AppLockService.swift
//  VultisigApp
//

import Foundation

/// Owns the app-lock policy: which gate is in use, how long the app may sit in
/// the background before re-locking, and whether returning to the foreground
/// should re-lock now.
///
/// The `LAContext` mechanics stay in `AppViewModel`; what lives here is the part
/// that used to be a hardcoded `interval > 60*5` buried in a scene-phase hook,
/// with no way for anyone to configure it and no way to test it.
final class AppLockService {

    static let shared = AppLockService()

    private enum Keys {
        static let mode = "appLockMode"
        static let interval = "autoLockIntervalMinutes"
        /// Shared with the pre-existing implementation so the stored timestamp
        /// carries across an upgrade rather than starting empty.
        static let lastRecordedTime = "lastRecordedTime"
        /// Legacy flag, still the source of truth until a mode is chosen.
        static let legacyAuthenticationEnabled = "isAuthenticationEnabled"
    }

    private let defaults: UserDefaults
    private let formatter = ISO8601DateFormatter()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Configuration

    /// Falls back to the legacy `isAuthenticationEnabled` flag until the user
    /// picks a mode, so upgrading preserves whatever the app was already doing —
    /// including the case where biometrics were unavailable and the flag was
    /// turned off programmatically.
    var mode: AppLockMode {
        get {
            if let raw = defaults.string(forKey: Keys.mode),
               let stored = AppLockMode(rawValue: raw) {
                return stored
            }
            let legacyEnabled = defaults.object(forKey: Keys.legacyAuthenticationEnabled) as? Bool ?? true
            return legacyEnabled ? .deviceAuth : .off
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.mode)
        }
    }

    var autoLockInterval: AutoLockInterval {
        get {
            guard let raw = defaults.object(forKey: Keys.interval) as? Int,
                  let interval = AutoLockInterval(rawValue: raw) else {
                return .default
            }
            return interval
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.interval)
        }
    }

    var isLockEnabled: Bool {
        mode != .off
    }

    // MARK: - Scene transitions

    /// Records that the app left the foreground.
    func noteBackgrounded(now: Date = Date()) {
        defaults.set(formatter.string(from: now), forKey: Keys.lastRecordedTime)
    }

    /// Whether returning to the foreground should re-lock, recording the moment
    /// either way so the next interval is measured from now.
    ///
    /// Reads before it writes — the answer depends on the previous timestamp.
    func evaluateForeground(now: Date = Date()) -> Bool {
        let shouldRelock = shouldRelock(now: now)
        defaults.set(formatter.string(from: now), forKey: Keys.lastRecordedTime)
        return shouldRelock
    }

    func shouldRelock(now: Date = Date()) -> Bool {
        guard isLockEnabled else { return false }

        guard let recorded = defaults.string(forKey: Keys.lastRecordedTime),
              let backgroundedAt = formatter.date(from: recorded) else {
            // Nothing recorded yet — a first launch, not a return from the
            // background. Locking here would gate the app on a timestamp that
            // never existed.
            return false
        }

        guard autoLockInterval != .immediate else { return true }

        // Strictly greater, matching the behaviour this replaced.
        return now.timeIntervalSince(backgroundedAt) > autoLockInterval.duration
    }
}
