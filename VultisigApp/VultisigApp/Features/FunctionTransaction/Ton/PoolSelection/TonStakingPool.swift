//
//  TonStakingPool.swift
//  VultisigApp
//
//  TON nominator-pool analog of `CosmosValidator` — the value-type the pool
//  picker renders and selects. Built from the tonapi.io `/v2/staking/pools`
//  list response.
//

import Foundation

/// The deposit/withdraw text comments a TON nominator-pool contract expects.
/// Nominator deposits are plain text comments, but each pool *implementation*
/// uses a DIFFERENT word — sending the wrong one is rejected on-chain
/// (exit 72). This is the single source of truth mapping a pool's tonapi
/// `implementation` string to its protocol tokens.
///
/// These are TON contract protocol tokens, NOT user-facing UI — never localize.
enum TonStakingComment {
    /// Standard nominator pool (`ton-blockchain/nominator-pool`): deposit "d".
    /// Whales pool (`tonwhales/ton-nominators`): deposit "Deposit" (capitalized) —
    /// verified against successful on-chain deposits; the repo README's "Stake"
    /// is stale and is rejected by the live pools (exit 72).
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

    /// tonapi `implementation` values that are genuine **nominator pools** — the
    /// only ones our `"d"`/`"w"` text-comment deposit mechanism can stake into.
    /// `liquidTF` (Tonstakers and similar) mints a jetton instead and must be
    /// excluded; unknown implementations are treated as non-nominator (excluded).
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
