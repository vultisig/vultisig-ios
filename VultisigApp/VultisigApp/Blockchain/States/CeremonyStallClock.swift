//
//  CeremonyStallClock.swift
//  VultisigApp
//

import Foundation

/// Trips when a ceremony has made no progress for `limit`. Progress is an
/// applied inbound message or an accepted outbound send: an outbound round
/// fans out to every peer and each send may spend its whole retry budget, so
/// a clock that only watched inbound traffic would fire on a party that is
/// still successfully talking to the relay.
struct CeremonyStallClock {
    static let defaultLimit: Duration = .seconds(60)

    let limit: Duration
    private let now: () -> ContinuousClock.Instant
    private var lastProgress: ContinuousClock.Instant

    init(limit: Duration = CeremonyStallClock.defaultLimit,
         now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.limit = limit
        self.now = now
        self.lastProgress = now()
    }

    mutating func reset() {
        lastProgress = now()
    }

    mutating func markProgress() {
        lastProgress = now()
    }

    var isStalled: Bool {
        now() - lastProgress > limit
    }
}
