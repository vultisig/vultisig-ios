//
//  SolanaStakingConfig.swift
//  VultisigApp
//
//  Constants for Solana native staking (Stake program) reads. The Stake
//  program account layout and the staker-authority memcmp offset are protocol
//  facts, not per-chain config, so this is a single flat constant set rather
//  than the per-chain `[Chain: Entry]` table that `CosmosStakingConfig` keeps —
//  but the shape (one config enum, an `isStakingSupported` predicate) mirrors
//  it so the two read layers stay legible side by side.
//
//  The min-delegation RPC (`getStakeMinimumDelegation`) is blocked by the
//  Vultisig proxy, and the 1 SOL program minimum is feature-gated / inactive on
//  mainnet today. So delegation-floor preflight uses the rent-exempt reserve
//  (fetched live via `getMinimumBalanceForRentExemption(200)`) plus the
//  documented `minDelegationFloorLamports` constant below as the substitute.
//

import Foundation

enum SolanaStakingConfig {
    /// The on-chain Stake program. Every stake account is owned by this program;
    /// it is also the `programId` argument to the stake-filtered
    /// `getProgramAccounts` scan.
    static let stakeProgramId = "Stake11111111111111111111111111111111111111"

    /// Byte size of a fully-initialized stake account (`StakeStateV2`). The
    /// `getProgramAccounts` scan filters on `dataSize: 200` to exclude
    /// uninitialized / rewards-pool accounts before the memcmp narrows to the
    /// owner's accounts.
    static let stakeStateSize = 200

    /// Offset of the staker authority pubkey inside the stake-account data, used
    /// as the `memcmp` offset to fetch only a given owner's stake accounts.
    /// Layout: 4-byte state enum discriminant + 8-byte `rentExemptReserve`
    /// (`Meta.rent_exempt_reserve`) = 12 bytes precede `Meta.authorized.staker`.
    static let stakerMemcmpOffset = 12

    /// Offset of the delegation `voter` (vote account) pubkey inside the
    /// stake-account data. Available for vote-account-scoped scans; the
    /// owner-scoped read uses `stakerMemcmpOffset`.
    static let voterMemcmpOffset = 124

    /// Documented substitute for the blocked min-delegation RPC. 1 SOL in
    /// lamports — the historical program minimum the feature gate would activate
    /// to. Used together with the live rent-exempt reserve as the delegation
    /// floor; kept as a named constant so the substitution is explicit rather
    /// than a magic number at the call site.
    static let minDelegationFloorLamports: UInt64 = 1_000_000_000

    /// Lamports per SOL (9 decimals). Shared by the staking read/format layer.
    static let lamportsPerSol: UInt64 = 1_000_000_000

    /// Mainnet schedule: 432,000 slots per epoch (~2 days). Informational —
    /// the live value is read from `getEpochInfo.slotsInEpoch`; this is the
    /// documented fallback for activation/cooldown copy.
    static let slotsPerEpoch: UInt64 = 432_000

    /// `u64::MAX` sentinel the Stake program writes into `deactivationEpoch`
    /// while a delegation is active (not deactivating). Parsed stake accounts
    /// carry this verbatim; the activation-state derivation treats it as
    /// "no deactivation scheduled".
    static let epochSentinel: UInt64 = .max

    /// Native SOL staking is supported only on the Solana chain.
    static func isStakingSupported(_ chain: Chain) -> Bool {
        chain.isSolanaStakingChain
    }
}
