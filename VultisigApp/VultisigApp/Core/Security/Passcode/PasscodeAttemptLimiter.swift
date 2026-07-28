//
//  PasscodeAttemptLimiter.swift
//  VultisigApp
//

import Foundation
import OSLog

private let logger = Log.app.store

enum PasscodeAttemptLimiterError: Error, Equatable {
    /// The attempt state could not be stored. Treated as fatal for the attempt:
    /// if failures cannot be recorded, the throttle does not exist.
    case persistenceFailed
    /// State is present but unreadable. Distinct from absent, because treating
    /// corruption as "no failures yet" would let corrupting the record reset the
    /// only throttle there is.
    case stateUnreadable
}

/// Throttles passcode guessing in the app.
///
/// This is the only thing standing between five digits and 100,000 tries, and it
/// protects the in-app path *only* — it is irrelevant to anyone holding the
/// stored blob, which is why the data key is a random 256 bits rather than
/// something derived from the passcode.
///
/// State lives in the Keychain rather than `UserDefaults` so it survives a
/// reinstall; a lockout that can be cleared by deleting and reinstalling the app
/// is not a lockout.
protocol PasscodeAttemptLimiting {
    /// How long the caller must wait before another attempt is allowed.
    func remainingLockout(now: Date) -> TimeInterval
    /// - Throws: when the failure could not be recorded, so the caller can
    ///   refuse the attempt rather than let an unthrottled one through.
    func recordFailure(now: Date) throws
    func recordSuccess()
}

final class PasscodeAttemptLimiter: PasscodeAttemptLimiting {

    /// No delay for the first few slips — fat fingers are not an attack.
    static let freeAttempts = 3
    /// Doubles per failure past the free ones: 5s, 10s, 20s, … capped below.
    static let baseDelay: TimeInterval = 5
    static let maximumDelay: TimeInterval = 15 * 60

    private let keychain: KeychainService
    private let uptime: () -> TimeInterval
    private let lock = NSLock()

    init(
        keychain: KeychainService = DefaultKeychainService.shared,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.keychain = keychain
        self.uptime = uptime
    }

    func remainingLockout(now: Date = Date()) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }

        let state: State?
        do {
            state = try loadState()
        } catch {
            // Unreadable state fails closed: the alternative is that corrupting
            // one Keychain item removes the throttle entirely.
            return Self.maximumDelay
        }

        guard let state, state.failureCount > Self.freeAttempts, let lastFailure = state.lastFailure else {
            return 0
        }

        guard let elapsed = elapsed(since: lastFailure, storedUptime: state.lastFailureUptime, now: now) else {
            // The device rebooted, so the stored uptime belongs to a different
            // boot and the wall clock cannot be trusted on its own. Restart the
            // delay from now rather than honour a possibly-manipulated interval,
            // and rebase the record so the lockout can actually expire.
            do {
                try store(State(failureCount: state.failureCount, lastFailure: now, lastFailureUptime: uptime()))
            } catch {
                // Without the rebase the stale high uptime is re-read on every
                // check and the delay restarts forever, so this must not pass
                // quietly as an ordinary, expiring lockout.
                logger.error("Could not rebase passcode lockout after reboot")
                return Self.maximumDelay
            }
            return delay(forFailureCount: state.failureCount)
        }

        let remaining = delay(forFailureCount: state.failureCount) - elapsed
        return max(0, min(remaining, Self.maximumDelay))
    }

    func recordFailure(now: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }

        let existing: State?
        do {
            existing = try loadState()
        } catch {
            // Unreadable rather than absent. Resuming from zero would mean
            // corrupting one Keychain item buys a fresh set of free attempts, so
            // it resumes from the throttled ceiling instead.
            existing = State(failureCount: Self.freeAttempts, lastFailure: now, lastFailureUptime: uptime())
        }

        let updated = State(
            failureCount: (existing?.failureCount ?? 0) + 1,
            lastFailure: now,
            lastFailureUptime: uptime()
        )
        try store(updated)
        logger.warning("Passcode attempt failed (\(updated.failureCount, privacy: .public) consecutive)")
    }

    func recordSuccess() {
        lock.lock()
        defer { lock.unlock() }

        // Best effort: a failure to clear leaves the user throttled, which is
        // the safe direction, so it does not need to abort anything.
        try? store(State(failureCount: 0, lastFailure: nil, lastFailureUptime: nil))
    }

    // MARK: - Elapsed time

    /// How much time counts as having passed since the last failure, or `nil`
    /// when the device has rebooted and no trustworthy answer exists.
    ///
    /// Wall time alone is user-adjustable — moving the device clock forward
    /// would clear every backoff — so within a single boot the monotonic uptime
    /// is used as well and the **smaller** of the two wins. Falling back to wall
    /// time across a reboot would hand back the whole bypass: set the clock
    /// forward, reboot, and the lockout is gone. So a reboot returns `nil` and
    /// the caller restarts the delay instead.
    private func elapsed(since lastFailure: Date, storedUptime: TimeInterval?, now: Date) -> TimeInterval? {
        let wallElapsed = max(0, now.timeIntervalSince(lastFailure))

        guard let storedUptime else { return wallElapsed }

        let uptimeElapsed = uptime() - storedUptime
        guard uptimeElapsed >= 0 else { return nil }

        return min(wallElapsed, uptimeElapsed)
    }

    private func delay(forFailureCount count: Int) -> TimeInterval {
        let excess = count - Self.freeAttempts
        guard excess > 0 else { return 0 }

        // Bound the exponent first: 2^excess overflows long before the delay cap
        // would otherwise bite.
        let doublings = min(excess - 1, 16)
        return min(Self.baseDelay * pow(2, Double(doublings)), Self.maximumDelay)
    }

    // MARK: - Storage

    private struct State: Codable {
        var failureCount: Int
        var lastFailure: Date?
        /// Monotonic uptime at the moment of the failure, for the clock check.
        var lastFailureUptime: TimeInterval?

        /// Any recorded failure must carry both clocks, or the checks that
        /// depend on them silently do nothing.
        var isSelfConsistent: Bool {
            guard failureCount >= 0 else { return false }
            guard failureCount > 0 else { return true }
            return lastFailure != nil && lastFailureUptime != nil
        }
    }

    /// - Returns: `nil` when no record exists at all — a genuinely fresh start.
    /// - Throws: when a record exists but cannot be decoded.
    private func loadState() throws -> State? {
        guard let data = keychain.getPasscodeAttemptState() else {
            return nil
        }
        guard let state = try? JSONDecoder().decode(State.self, from: data) else {
            logger.error("Passcode attempt state is present but unreadable")
            throw PasscodeAttemptLimiterError.stateUnreadable
        }

        // Decoding is not enough. A record with failures but no timestamp would
        // slip past the lockout entirely, and one with no uptime would restore
        // the clock-forward bypass — both are reachable by editing the stored
        // blob, so they count as unreadable rather than as valid state.
        guard state.isSelfConsistent else {
            logger.error("Passcode attempt state is internally inconsistent")
            throw PasscodeAttemptLimiterError.stateUnreadable
        }
        return state
    }

    /// Verifies the write landed. A silently dropped write would mean failures
    /// stop being counted, i.e. the throttle quietly stops existing.
    private func store(_ state: State) throws {
        guard let data = try? JSONEncoder().encode(state) else {
            logger.error("Failed to encode passcode attempt state")
            throw PasscodeAttemptLimiterError.persistenceFailed
        }

        keychain.setPasscodeAttemptState(data)

        guard keychain.getPasscodeAttemptState() == data else {
            logger.error("Passcode attempt state failed read-back verification")
            throw PasscodeAttemptLimiterError.persistenceFailed
        }
    }
}
