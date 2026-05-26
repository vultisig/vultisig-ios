//
//  CosmosStakingConfig.swift
//  VultisigApp
//
//  Per-chain configuration for Cosmos-SDK x/staking + x/distribution flows.
//  The table is the sole gas / fee / valoper-prefix source for the delegate,
//  undelegate, redelegate and withdraw-reward msg encoders — every consumer
//  goes through `entry(for:)` so we never hand-roll gas budgets at call sites.
//
//  Values mirror the agent app's `COSMOS_CHAIN_CONFIG` table at
//  `vultiagent-app/src/services/cosmosTx.ts` and the SDK's
//  `BuildCosmosStakingOptions` consumer contract. Adding a chain here also
//  promotes it into the staking-allowlist semantics (`isStakingSupported`).
//

import Foundation

enum CosmosStakingConfig {
    /// Per-chain staking parameters. `bondDenom` and `feeDenom` are identical
    /// for both Terra chains today; the distinction is kept because Cosmos
    /// chains exist where they differ (chains that pay fees in a non-bond
    /// denom — e.g. dYdX where the bond denom is uadydx but fees pay in
    /// USDC). Future chain additions will exercise that asymmetry.
    struct Entry: Equatable {
        let chainId: String
        let bondDenom: String
        let feeDenom: String
        let valoperHrp: String
        /// Gas units to budget for a single-msg tx on this chain.
        /// Multi-msg batched txs scale linearly (see `cosmosTx.ts:858-867`).
        let gasLimit: UInt64
        /// Fee amount in `feeDenom` base units for a single-msg tx.
        let feeAmount: UInt64
        /// Cosmos-SDK unbonding period — 21 days canonical default; both
        /// Terra chains keep it. Surfaced via "21-day unbonding lock" UX
        /// microcopy on the active-delegation card.
        let unbondingDays: Int
    }

    /// The allowlist + gas / fee / valoper-prefix table. Keying staking
    /// support purely off `table.keys` means there's no second list to
    /// maintain — `isStakingSupported(.thorChain)` returns false even
    /// though THORChain is a Cosmos-SDK chain, because THOR uses its own
    /// bond model rather than x/staking.
    ///
    /// LUNC gas (1.5M units / 100M uluna) is the empirically-verified
    /// floor — agent-app txs `534BFEF22F…` (delegate) and `200345EA31…`
    /// (withdraw-rewards) used 1.07M gas with 28% headroom; smaller
    /// budgets OoG on `columbus-5`.
    static let table: [Chain: Entry] = [
        .terra: Entry(
            chainId: "phoenix-1",
            bondDenom: "uluna",
            feeDenom: "uluna",
            valoperHrp: "terravaloper",
            gasLimit: 300_000,
            feeAmount: 7_500,
            unbondingDays: 21
        ),
        .terraClassic: Entry(
            chainId: "columbus-5",
            bondDenom: "uluna",
            feeDenom: "uluna",
            valoperHrp: "terravaloper",
            gasLimit: 1_500_000,
            feeAmount: 100_000_000,
            unbondingDays: 21
        )
    ]

    static func entry(for chain: Chain) throws -> Entry {
        guard let entry = table[chain] else {
            throw CosmosStakingConfigError.unsupportedChain(chain)
        }
        return entry
    }

    static func isStakingSupported(_ chain: Chain) -> Bool {
        table[chain] != nil
    }

    static func chainId(for chain: Chain) throws -> String {
        try entry(for: chain).chainId
    }

    static func bondDenom(for chain: Chain) throws -> String {
        try entry(for: chain).bondDenom
    }

    static func feeDenom(for chain: Chain) throws -> String {
        try entry(for: chain).feeDenom
    }

    static func valoperHrp(for chain: Chain) throws -> String {
        try entry(for: chain).valoperHrp
    }

    static func gasLimit(for chain: Chain) throws -> UInt64 {
        try entry(for: chain).gasLimit
    }

    static func feeAmount(for chain: Chain) throws -> UInt64 {
        try entry(for: chain).feeAmount
    }

    static func unbondingDays(for chain: Chain) throws -> Int {
        try entry(for: chain).unbondingDays
    }
}

enum CosmosStakingConfigError: Error, LocalizedError, Equatable {
    case unsupportedChain(Chain)

    var errorDescription: String? {
        switch self {
        case .unsupportedChain(let chain):
            return String(format: "cosmosStakingErrorUnsupportedChain".localized, chain.name)
        }
    }
}
