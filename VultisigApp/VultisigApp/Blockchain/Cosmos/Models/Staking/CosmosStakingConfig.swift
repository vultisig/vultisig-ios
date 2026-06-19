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

import BigInt
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
    /// Gas budgets are empirically-verified floors with headroom for the
    /// heaviest single-msg path, MsgBeginRedelegate. Phoenix-1 redelegate
    /// was observed at 300_140 gas in vultisig-android mainnet tx
    /// `44A3CE6C…EAF31` (OoG against the prior 300_000 floor) so the Terra
    /// floor was raised to 400_000 with proportional fee. LUNC bumped to
    /// 2M for the same dual-record allowance, fee scaled to preserve the
    /// prior ~66.6667 uluna/gas ratio (133_333_334 / 2M).
    static let table: [Chain: Entry] = [
        .terra: Entry(
            chainId: "phoenix-1",
            bondDenom: "uluna",
            feeDenom: "uluna",
            valoperHrp: "terravaloper",
            // Bumped from 300_000 -> 400_000 after observed OoG on redelegate
            // (vultisig-android #4687 tx 44A3CE6C…EAF31, gasUsed 300_140).
            gasLimit: 400_000,
            feeAmount: 10_000,
            unbondingDays: 21
        ),
        .terraClassic: Entry(
            chainId: "columbus-5",
            bondDenom: "uluna",
            feeDenom: "uluna",
            valoperHrp: "terravaloper",
            // Bumped 1.5M -> 2M for redelegate headroom; fee scaled to keep
            // gas-price ratio (~66.6667 uluna/gas) constant.
            gasLimit: 2_000_000,
            feeAmount: 133_333_334,
            unbondingDays: 21
        ),
        // QBTC (post-quantum) is a Cosmos-SDK chain that signs with ML-DSA, not
        // secp256k1, so it takes the `CosmosStakingSignDataResolver.resolveMLDSA`
        // branch (NOT the secp256k1 `.resolve`): that branch skips the 33-byte
        // secp256k1 pubkey guard and stamps `/cosmos.crypto.mldsa.PubKey`, then
        // shares the same `buildSignDirect` AuthInfo/TxBody path. `QBTCHelper`
        // consumes the resulting `signDirect` bytes verbatim. So QBTC's signed
        // gas / fee come from THIS entry via the resolver, same as the Terra
        // chains. This entry is also the single source of truth for denom /
        // valoper-prefix / gas / fee / unbonding everywhere else (read surfaces,
        // balance preflight, validator bech32 preflight). `bondDenom` is
        // lowercase `qbtc` (8 decimals, NOT a micro-denom).
        //
        // `min_gas_price` = 0 and `min_tx_fee` = 800 on qbtc are constant
        // / un-queryable ante values, so the fee floor is the flat `min_tx_fee`
        // (800) and the only dynamic dimension is the gas_limit. `gasLimit` is
        // 1_000_000: an on-device undelegate measured 401_486 gas (the prior
        // 400_000 OoG'd it), redelegate is heavier still, and the chain's
        // `block.max_gas` is -1 (unlimited). Because `min_gas_price` is 0 the fee
        // is decoupled from gas, so a generous limit that never OoGs costs
        // nothing — better than inching it up per message type.
        // `feeAmount` is the 800 `min_tx_fee` floor (the prior 7_500 was the
        // carried-over generic Cosmos send default, ~9x the floor).
        .qbtc: Entry(
            chainId: QBTCChain.chainID,
            bondDenom: "qbtc",
            feeDenom: "qbtc",
            valoperHrp: "qbtcvaloper",
            gasLimit: 1_000_000,
            feeAmount: 800,
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

    // MARK: - Linear gas / fee scaling

    // Single source of truth for the `base × msgCount` scaling. Both the
    // SignDoc resolver (the SIGNED fee baked into AuthInfo) and the verify
    // screen (the DISPLAYED / balance-preflighted fee) call these, so the
    // shown fee can never drift from the signed one. A single-msg flow uses
    // msgCount 1, which collapses to the per-chain base values; a batched
    // withdraw-rewards tx scales by its validator count. msgCount is clamped
    // to >= 1 to mirror the resolver's `max(msgsAny.count, 1)`.

    static func scaledGasLimit(for chain: Chain, msgCount: Int) throws -> UInt64 {
        try gasLimit(for: chain) * UInt64(max(msgCount, 1))
    }

    static func scaledFeeAmount(for chain: Chain, msgCount: Int) throws -> UInt64 {
        try feeAmount(for: chain) * UInt64(max(msgCount, 1))
    }

    /// Scaled fee as `BigInt`, for `SendTransaction.gas` (the value the verify
    /// screen renders via `gasInReadable` and prices via `feesInReadable`).
    static func scaledFeeAmountBigInt(for chain: Chain, msgCount: Int) throws -> BigInt {
        BigInt(try scaledFeeAmount(for: chain, msgCount: msgCount))
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
