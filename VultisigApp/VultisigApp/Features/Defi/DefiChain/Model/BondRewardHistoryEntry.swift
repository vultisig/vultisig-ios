//
//  BondRewardHistoryEntry.swift
//  VultisigApp
//
//  One past realized reward — the "dated row" the Total Rewards Earned sheet
//  renders below the live Upcoming row. THOR and Maya bonds produce it per
//  churn via `BondRewardMath`; TCY staking produces it per daily payout.
//

import Foundation

struct BondRewardHistoryEntry: Identifiable, Equatable, Sendable, Codable {
    /// Unique within one history: the churn height for a bond, the payout's
    /// unix second for TCY staking (Midgard sends no height for those).
    let id: Int
    let date: Date
    /// Base units of the sheet's coin.
    let amount: Decimal
}

extension BondRewardHistoryEntry {
    init(churnHeight: Int, churnDate: Date, amount: Decimal) {
        self.init(id: churnHeight, date: churnDate, amount: amount)
    }
}

/// The rewards a history sheet can show, and whether that is all of them.
struct BondRewardHistory: Equatable, Sendable {
    /// Newest first.
    let entries: [BondRewardHistoryEntry]
    /// `false` when a reward that should be in `entries` could not be loaded,
    /// so the sheet's total may be short.
    let isComplete: Bool
}

/// The outcome of one historical `?height=` query, distinguishing a
/// successfully decoded "not a bond provider here" snapshot (the legitimate
/// stop-walking-backward signal) from a network/decode failure, which marks
/// the history incomplete instead — see `BondRewardHistoryWalker`.
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
