//
//  KaminoComputeBudget.swift
//  VultisigApp
//

import Foundation

/// Compute-budget parameters for the ComputeBudget instructions the app injects
/// into Kamino's transactions.
///
/// Kamino builds its transactions with **no** ComputeBudget instruction at all,
/// and ignores `priorityFeeLamports` / `computeUnitPriceMicroLamports` in the
/// request body — the response is byte-identical with or without them. So the
/// only way a Kamino transaction carries a priority fee is for the app to inject
/// one, and injecting a price without a limit would price the fee off the
/// runtime's default limit rather than the units the transaction actually needs.
enum KaminoComputeBudget {

    /// Compute units measured on mainnet with `simulateTransaction`
    /// (`err: null`): USDC deposit 252,146 · SOL deposit 287,029 · withdraw
    /// 174,566. Each limit below carries roughly a quarter more, which absorbs
    /// the drift a different account-existence mix causes — a deposit whose
    /// share ATA or farm user account still has to be created does strictly more
    /// work than one whose accounts already exist.
    ///
    /// These are deliberately NOT `SolanaHelper.priorityFeeLimit`. That constant
    /// is 100,000 CU, which sits below what every one of the three transactions
    /// consumes, so reusing it would abort each of them on compute exhaustion.
    static let tokenDepositUnitLimit: UInt32 = 320_000
    /// A SOL-vault deposit additionally creates the wSOL account, transfers into
    /// it and syncs it, so it costs more than a token deposit.
    static let nativeDepositUnitLimit: UInt32 = 350_000
    static let withdrawUnitLimit: UInt32 = 220_000

    /// Price used when the network's recent-fee sample is unavailable, in
    /// micro-lamports per compute unit. The live median from
    /// `getRecentPrioritizationFees` is preferred; this is the floor beneath it.
    ///
    /// The priority fee is `price × limit`, so the limits above bound the cost
    /// as well as the compute: at 320,000 units this price is 6,400 lamports
    /// (0.0000064 SOL) on top of the base fee.
    static let fallbackUnitPriceMicroLamports: UInt64 = 20_000

    /// Ceiling on the live price, in micro-lamports per compute unit.
    ///
    /// The network's recent-fee sample is a number a remote node hands us, and
    /// it is multiplied by a six-figure compute limit to produce lamports the
    /// user pays. Unbounded, a wrong or hostile sample is an unbounded fee. At
    /// this ceiling and the largest limit above, the priority fee tops out at
    /// `350,000 × 1,000,000 / 1,000,000` = 350,000 lamports (0.00035 SOL) —
    /// generous against any real congestion, and still small.
    static let maxUnitPriceMicroLamports: UInt64 = 1_000_000

    /// Compute-unit limit for a deposit into `vault`.
    static func depositUnitLimit(for vault: KaminoVaultInfo) -> UInt32 {
        vault.isWrappedSolVault ? nativeDepositUnitLimit : tokenDepositUnitLimit
    }

    /// Brings a sampled network price inside `[fallback, max]`.
    ///
    /// The fallback is a floor rather than a default: a sample below it would
    /// under-tip a transaction that has to land before its blockhash expires.
    static func clampedUnitPrice(_ sampled: UInt64) -> UInt64 {
        min(max(sampled, fallbackUnitPriceMicroLamports), maxUnitPriceMicroLamports)
    }
}
