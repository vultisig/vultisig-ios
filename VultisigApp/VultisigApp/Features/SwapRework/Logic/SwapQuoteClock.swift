//
//  SwapQuoteClock.swift
//  VultisigApp
//
//  How old the quote on screen is. The form refreshes it every
//  `SwapReworkConfig.quoteLifetime` seconds; when a refresh does not land in
//  time (offline, provider down) the quote expires and review is blocked
//  until a new one arrives, rather than letting a stale amount reach signing.
//

import Foundation

struct SwapQuoteClock: Equatable {
    enum State: Equatable {
        /// No quote yet.
        case idle
        /// Valid, with whole seconds until the next refresh.
        case live(secondsLeft: Int)
        /// Past its refresh time, a refresh is in flight.
        case refreshing
        /// Past the grace window with no new quote. Review is blocked.
        case expired
    }

    let lifetime: TimeInterval
    let grace: TimeInterval
    private(set) var receivedAt: Date?

    init(
        lifetime: TimeInterval = SwapReworkConfig.quoteLifetime,
        grace: TimeInterval = SwapReworkConfig.quoteExpiryGrace
    ) {
        self.lifetime = lifetime
        self.grace = grace
    }

    mutating func quoteReceived(at date: Date) {
        receivedAt = date
    }

    mutating func reset() {
        receivedAt = nil
    }

    func state(at now: Date) -> State {
        guard let receivedAt else { return .idle }
        let age = now.timeIntervalSince(receivedAt)
        if age < lifetime {
            return .live(secondsLeft: max(1, Int((lifetime - age).rounded(.up))))
        }
        return age < lifetime + grace ? .refreshing : .expired
    }

    /// 1 when fresh, 0 when due. Drives the countdown ring.
    func remainingFraction(at now: Date) -> Double {
        guard let receivedAt, lifetime > 0 else { return 0 }
        let left = lifetime - now.timeIntervalSince(receivedAt)
        return min(max(left / lifetime, 0), 1)
    }

    func isExpired(at now: Date) -> Bool {
        state(at: now) == .expired
    }

    /// "0:47"
    static func countdownText(seconds: Int) -> String {
        let clamped = max(seconds, 0)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
