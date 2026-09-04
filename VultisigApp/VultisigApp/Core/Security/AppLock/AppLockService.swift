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
        static let intervalSeconds = "autoLockIntervalSeconds"
        static let legacyIntervalMinutes = "autoLockIntervalMinutes"
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
            if let raw = defaults.object(forKey: Keys.intervalSeconds) as? Int {
                return AutoLockInterval(rawValue: raw) ?? .default
            }

            guard let legacyMinutes = defaults.object(forKey: Keys.legacyIntervalMinutes) as? Int else {
                return .default
            }

            return Self.intervalMigrated(fromMinutes: legacyMinutes) ?? .default
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.intervalSeconds)

            if let legacyMinutes = newValue.legacyMinutes {
                defaults.set(legacyMinutes, forKey: Keys.legacyIntervalMinutes)
            } else {
                defaults.removeObject(forKey: Keys.legacyIntervalMinutes)
            }
        }
    }

    private static func intervalMigrated(fromMinutes minutes: Int) -> AutoLockInterval? {
        switch minutes {
        case 0: .immediate
        case 1: .oneMinute
        case 5: .fiveMinutes
        case 10: .tenMinutes
        case 15: .fifteenMinutes
        case 30: .thirtyMinutes
        default: nil
        }
    }

    var isLockEnabled: Bool {
        mode != .off
    }

    // MARK: - The app's own system prompts

    /// How many system authentication prompts the app itself currently has on
    /// screen.
    ///
    /// Main-thread only, and not persisted: it describes what is on the display
    /// right now, and a launch has none of them up by definition.
    private var systemAuthPromptCount = 0
    /// Bumped whenever the count is dropped wholesale, so that a completion
    /// belonging to a prompt from before the drop cannot decrement a prompt
    /// raised after it.
    ///
    /// Without it the pairing is by count alone, and a count cannot tell whose
    /// completion it is: a prompt outstanding when the app backgrounds has its
    /// completion delivered *later*, by which time ``forgetSystemAuthPrompts()``
    /// has reset everything and the user may have raised a new one. The stale
    /// completion would decrement the new prompt's count to zero and the cover
    /// would go up over it — the exact flash this exists to prevent, arriving by
    /// the back door.
    private var systemAuthPromptGeneration = 0

    /// A prompt's claim on the count, handed out by ``beginSystemAuthPrompt()``
    /// and spent by ``endSystemAuthPrompt(_:)``.
    ///
    /// Opaque on purpose: the only correct thing a caller can do with it is give
    /// it back exactly once, so it carries nothing else.
    struct SystemAuthPromptTicket {
        fileprivate let generation: Int
    }

    /// Whether an `.inactive` arriving now is one the app caused by raising a
    /// prompt, rather than the app going anywhere.
    ///
    /// The privacy cover goes up on `.inactive`, which is right for a departure
    /// and wrong for this: a `LAContext` prompt makes the app inactive without
    /// it leaving, and covering there paints the logo over the very screen the
    /// user is authenticating *for* — on the fast-signing path, a cover
    /// appearing between Verify and Signing, over a Face ID sheet the app raised
    /// itself.
    ///
    /// It is the same distinction `AppViewModel`'s `didBackgroundSinceForeground`
    /// draws for the re-lock half of this family — an activation that followed
    /// no departure is not a return — reaching the cover half, which that flag
    /// never covered.
    ///
    /// This is deliberately **not** consulted for a real backgrounding. That
    /// arrives as `.background`, where the cover goes up unconditionally.
    var isPresentingSystemAuthPrompt: Bool {
        systemAuthPromptCount > 0
    }

    /// Called immediately before a prompt is raised rather than after, because
    /// the `.inactive` it causes can arrive before the call that raised it has
    /// returned.
    ///
    /// A count rather than a flag because prompts can overlap, and because a
    /// balanced pair is the most a caller can honestly promise.
    func beginSystemAuthPrompt() -> SystemAuthPromptTicket {
        systemAuthPromptCount += 1
        return SystemAuthPromptTicket(generation: systemAuthPromptGeneration)
    }

    /// The other half, required on **every** path out of a prompt — success,
    /// failure and cancellation alike. A prompt the user dismissed is still a
    /// prompt that is gone.
    ///
    /// A ticket from before the last ``forgetSystemAuthPrompts()`` is spent
    /// silently: the prompt it belonged to was already accounted for when the
    /// app left, and the count it would decrement now belongs to somebody else.
    func endSystemAuthPrompt(_ ticket: SystemAuthPromptTicket) {
        guard ticket.generation == systemAuthPromptGeneration else { return }
        systemAuthPromptCount = max(0, systemAuthPromptCount - 1)
    }

    /// Drops the count on the floor, for the one caller that knows better than
    /// it does: a real backgrounding took the app and every prompt over it away
    /// together.
    ///
    /// Balanced calls are never trusted to be balanced. A completion that never
    /// arrives would otherwise leave the app permanently uncoverable, which is
    /// the one failure this must not have — and every ticket outstanding at this
    /// moment is invalidated with the count, so the completions that *do* arrive
    /// late cannot spend themselves against whatever comes next.
    func forgetSystemAuthPrompts() {
        systemAuthPromptCount = 0
        systemAuthPromptGeneration &+= 1
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

        switch autoLockInterval {
        case .immediate:
            return true
        case .never:
            return false
        default:
            break
        }

        let elapsed = now.timeIntervalSince(backgroundedAt)

        // A negative elapsed time means the recorded moment is in the future,
        // which the clock only reaches by being moved backwards while the app
        // was away. Read literally that is "no time has passed" and the app
        // stays open — a lock anyone can defer indefinitely by changing the date
        // is not a lock. Treat it as expired: the one thing known for certain is
        // that the stored timestamp can no longer be measured against.
        guard elapsed >= 0 else { return true }

        // Strictly greater, matching the behaviour this replaced.
        return elapsed > autoLockInterval.duration
    }
}

private extension AutoLockInterval {
    var legacyMinutes: Int? {
        switch self {
        case .immediate: 0
        case .oneMinute: 1
        case .fiveMinutes: 5
        case .tenMinutes: 10
        case .fifteenMinutes: 15
        case .thirtyMinutes: 30
        case .fifteenSeconds, .thirtySeconds, .never: nil
        }
    }
}
