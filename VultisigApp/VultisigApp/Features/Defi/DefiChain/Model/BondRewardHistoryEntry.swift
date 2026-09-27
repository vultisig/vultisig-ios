//
//  BondRewardHistoryEntry.swift
//  VultisigApp
//
//  One past churn's realized reward for a bond provider — the "dated row"
//  the Total Rewards Earned sheet renders below the live Upcoming row.
//  Chain-agnostic: THOR and Maya both produce this from their own node
//  details response via `BondRewardMath`.
//

import Foundation

struct BondRewardHistoryEntry: Identifiable, Equatable, Sendable {
    var id: Int { churnHeight }
    let churnHeight: Int
    let churnDate: Date
    let amount: Decimal
}

/// The outcome of one historical `?height=` query, distinguishing a
/// successfully decoded "not a bond provider here" snapshot (the legitimate
/// stop-walking-backward signal) from a network/decode failure (which must
/// propagate as an error rather than being read as the same signal — see
/// `getBondRewardHistory` on both chain API services).
enum BondRewardHistoryQueryResult: Sendable {
    case found(BondRewardHistoryEntry)
    case notAProvider
    case failed(Error)
}

enum BondRewardHistoryConfig {
    /// Cap on how many past churns the rewards-earned sheet considers. Well
    /// below the network's full churn history (400+) — the sheet renders
    /// recent history, not an audit trail.
    static let limit = 20
    /// How many historical `?height=` queries run at once while building the
    /// sheet's history.
    static let concurrency = 5
}
