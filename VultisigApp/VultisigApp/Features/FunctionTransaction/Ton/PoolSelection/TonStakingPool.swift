//
//  TonStakingPool.swift
//  VultisigApp
//
//  TON nominator-pool analog of `CosmosValidator` — the value-type the pool
//  picker renders and selects. Built from the tonapi.io `/v2/staking/pools`
//  list response.
//

import Foundation

/// TON contract protocol tokens by pool implementation. These are not localized.
enum TonStakingComment {
    /// Whales pools require `Deposit`; their documented `Stake` is rejected.
    static func deposit(for implementation: String?) -> String? {
        switch implementation {
        case "tf": return "d"
        case "whales": return "Deposit"
        default: return nil
        }
    }

    /// Standard nominator pool withdraw "w"; Whales withdraw "Withdraw".
    static func withdraw(for implementation: String?) -> String? {
        switch implementation {
        case "tf": return "w"
        case "whales": return "Withdraw"
        default: return nil
        }
    }
    /// Derived from the writer table so reader and builder tokens cannot drift.
    static var depositComments: Set<String> {
        Set(TonStakingPool.nominatorImplementations.compactMap { deposit(for: $0) })
    }

    static var withdrawComments: Set<String> {
        Set(TonStakingPool.nominatorImplementations.compactMap { withdraw(for: $0) })
    }
}

struct TonStakingPool: Equatable, Hashable {
    /// Pool contract address (raw `0:…` form from tonapi). Becomes the `"d"`
    /// memo destination once selected.
    let address: String
    let name: String
    /// Annual percentage yield as a percentage (e.g. `13.27` = 13.27%).
    let apy: Double
    /// Minimum stake in human-decimal TON.
    let minStake: Decimal
    let verified: Bool
    let currentNominators: Int?
    let maxNominators: Int?
    let implementation: String?

    /// Supported nominator implementations; liquid pools use a different flow.
    static let nominatorImplementations: Set<String> = ["whales", "tf"]

    /// Whether this is a nominator pool our deposit mechanism supports.
    var isNominatorPool: Bool {
        guard let implementation else { return false }
        return Self.nominatorImplementations.contains(implementation)
    }

    /// The deposit text comment this pool's contract expects, resolved from its
    /// `implementation`. `nil` for unsupported implementations.
    var depositComment: String? {
        TonStakingComment.deposit(for: implementation)
    }

    /// Whether the pool has room for another nominator. Pools at capacity are
    /// hidden from the picker since a stake to them would be rejected.
    var hasCapacity: Bool {
        guard let current = currentNominators, let max = maxNominators, max > 0 else {
            return true
        }
        return current < max
    }

    /// Maps a tonapi list entry into the picker model, scaling `min_stake`
    /// (nanotons) to human-decimal TON.
    init(entry: TonStakingPoolListEntry, decimals: Int) {
        self.address = entry.address
        self.name = entry.name
        self.apy = entry.apy
        self.minStake = Decimal(entry.minStake) / pow(Decimal(10), decimals)
        self.verified = entry.verified
        self.currentNominators = entry.currentNominators
        self.maxNominators = entry.maxNominators
        self.implementation = entry.implementation
    }
}
