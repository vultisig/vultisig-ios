//
//  WithdrawTransactionBuilder.swift
//  VultisigApp
//
//  Per-flow builder for a Solana native-staking withdraw. A pure value-type
//  carrier; the unsigned transaction bytes are produced lazily by
//  `SolanaStakingSignDataResolver.resolveWithdraw(...)` at Verify →
//  KeysignPayload bridge time so the recent blockhash is always fresh. Analog
//  of `SolanaDelegateTransactionBuilder`.
//
//  Withdraw moves the cooled-down lamports (delegated stake + auto-compounded
//  rewards) from the stake account back to the wallet. The CTA is gated upstream
//  on full inactivity (`SolanaEpochCooldownGate`); there is no rewards-claim op.
//

import BigInt
import Foundation
import VultisigCommonData

struct SolanaWithdrawTransactionBuilder: TransactionBuilder {
    let coin: Coin
    /// Source stake account being withdrawn from.
    let stakeAccount: String
    /// Human-decimal SOL amount to withdraw (the whole withdrawable balance).
    let amount: String

    /// The full withdrawable balance is always moved, so this is effectively a
    /// max send; the value travels via the staking payload, not the amount path.
    var sendMaxAmount: Bool { true }

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        ThreadSafeDictionary<String, String>()
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }

    /// `toAddress` doubles as the verify-screen "destination" — the withdrawn
    /// lamports return to the wallet's own address.
    var toAddress: String { coin.address }

    var solanaStakingPayload: SolanaStakingPayload? {
        let lamports = lamports(from: amount, decimals: coin.decimals)
        return SolanaStakingPayload.withdraw(stakeAccount: stakeAccount, lamports: lamports)
    }

    /// Converts a human-decimal SOL amount into lamports. Uses `BigInt` to
    /// avoid `Double` rounding at the 9-decimal scale, then clamps to the
    /// `UInt64` range the wallet-core stake proto expects.
    private func lamports(from amount: String, decimals: Int) -> UInt64 {
        let raw = amount.toBigInt(decimals: decimals)
        guard raw > 0, raw <= BigInt(UInt64.max) else { return 0 }
        return UInt64(raw)
    }
}
