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

/// The outcome of one historical `?height=` query, distinguishing a
/// successfully decoded "not a bond provider here" snapshot (the legitimate
/// stop-walking-backward signal) from a network/decode failure, which also
/// ends the walk — see `BondRewardHistoryWalker`.
enum BondRewardHistoryQueryResult: Sendable {
    case found(BondRewardHistoryEntry)
    case notAProvider
    case failed(Error)
}

enum BondRewardHistoryConfig {
    /// Only churns this recent are read from the node: liquify keeps about 13 days of state.
    static let fetchWindow: TimeInterval = 13 * 24 * 60 * 60
    /// How many historical `?height=` queries run at once while building the
    /// sheet's history.
    static let concurrency = 5
    /// Midgard's largest `limit` for `/actions`.
    static let unbondPageSize = 50
}
