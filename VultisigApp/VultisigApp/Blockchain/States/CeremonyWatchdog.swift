//
//  CeremonyWatchdog.swift
//  VultisigApp
//

import Foundation

/// Bounds both how long this party waits for a peer and how long the complete
/// algorithm ceremony may run. A new cryptographic retry starts a fresh peer
/// wait, but it never moves the hard deadline.
struct CeremonyWatchdog {
    static let defaultPeerWaitLimit: Duration = .seconds(60)
    /// Four historical attempts, each with the old nominal 60-second ceiling.
    static let defaultHardLimit: Duration = .seconds(240)

    struct RequestBudget {
        let timeoutInterval: TimeInterval
        let timeoutError: CeremonyTimeoutError
    }

    let peerWaitLimit: Duration
    let hardLimit: Duration?
    private let now: () -> ContinuousClock.Instant
    private let startedAt: ContinuousClock.Instant
    private var waitingSince: ContinuousClock.Instant

    init(peerWaitLimit: Duration = CeremonyWatchdog.defaultPeerWaitLimit,
         hardLimit: Duration? = CeremonyWatchdog.defaultHardLimit,
         now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.peerWaitLimit = peerWaitLimit
        self.hardLimit = hardLimit
        self.now = now
        let instant = now()
        self.startedAt = instant
        self.waitingSince = instant
    }

    var hardDeadline: ContinuousClock.Instant? {
        hardLimit.map { startedAt.advanced(by: $0) }
    }

    /// A retry owns a fresh native session, so it receives a new peer-response
    /// window while remaining inside the original ceremony hard deadline.
    mutating func beginAttempt() {
        waitingSince = now()
    }

    /// Called after this party has applied input and finished its complete
    /// outbound batch. From this point it is waiting for another participant.
    mutating func beginWaitingForPeer() {
        waitingSince = now()
    }

    func checkHardDeadline() throws {
        if let hardDeadline, now() >= hardDeadline {
            throw CeremonyTimeoutError.overallDeadlineExceeded
        }
    }

    func checkExpired() throws {
        let current = now()
        if let hardDeadline, current >= hardDeadline {
            throw CeremonyTimeoutError.overallDeadlineExceeded
        }
        if current >= waitingSince.advanced(by: peerWaitLimit) {
            throw CeremonyTimeoutError.peerUnresponsive
        }
    }

    /// Clips non-polling relay work to the remaining hard ceremony budget.
    /// Peer waiting does not apply while this party is completing local work.
    func hardRequestTimeout(maximum: TimeInterval) throws -> TimeInterval {
        try checkHardDeadline()
        guard let hardDeadline else {
            return maximum
        }
        let remaining = Self.timeInterval(now().duration(to: hardDeadline))
        return min(maximum, max(remaining, 0.001))
    }

    /// Gives a relay poll the exact time remaining until the first ceremony
    /// deadline. If the request itself times out, `timeoutError` identifies the
    /// deadline that won instead of leaking a transport-level timeout.
    func pollRequestBudget() throws -> RequestBudget {
        try checkExpired()
        let current = now()
        let peerDeadline = waitingSince.advanced(by: peerWaitLimit)
        let deadline: ContinuousClock.Instant
        let error: CeremonyTimeoutError
        if let hardDeadline, hardDeadline < peerDeadline {
            deadline = hardDeadline
            error = .overallDeadlineExceeded
        } else {
            deadline = peerDeadline
            error = .peerUnresponsive
        }
        return RequestBudget(
            timeoutInterval: max(Self.timeInterval(current.duration(to: deadline)), 0.001),
            timeoutError: error
        )
    }

    private static func timeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

enum CeremonyTimeoutError: Error, LocalizedError, Equatable {
    case peerUnresponsive
    case overallDeadlineExceeded

    var errorDescription: String? {
        switch self {
        case .peerUnresponsive:
            return "ceremonyPeerUnresponsive".localized
        case .overallDeadlineExceeded:
            return "ceremonyOverallDeadlineExceeded".localized
        }
    }
}
