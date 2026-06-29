//
//  MoveStakeTransactionBuilder.swift
//  VultisigApp
//
//  Per-flow builder for one sub-step of a guided Solana move-stake (redelegate
//  A → B). Solana has no native redelegate, so a move is a multi-transaction,
//  cross-epoch flow:
//
//    split off the chosen amount (partial moves) → deactivate the moved account
//      → wait ~1 epoch cooldown → re-delegate the moved account to validator B.
//
//  A whole-account move skips the split. Each sub-step is a separate keysign, so
//  the builder is parameterized by `step`: the move-stake input screen emits the
//  `.deactivate` step, and the "Finish moving to B" resume CTA emits the
//  `.redelegate` step once the account has cooled down.
//
//  Like the other staking builders this is a pure value-type carrier; the
//  unsigned bytes are produced lazily by `SolanaStakingSignDataResolver` at
//  Verify → KeysignPayload bridge time so the recent blockhash stays fresh.
//
//  Account for the rent-exempt reserve on the split destination: a `.split`
//  carries the chosen amount, and the split account must additionally hold the
//  rent reserve (handled by the ViewModel's stakeable-balance headroom).
//

import BigInt
import Foundation
import VultisigCommonData

struct SolanaMoveStakeTransactionBuilder: TransactionBuilder {
    let coin: Coin
    /// The account being moved (the source account for a whole-account move, or
    /// the carved split account once a partial move's split has landed).
    let stakeAccount: String
    /// Destination validator vote account (B).
    let votePubkey: String
    /// The active sub-step this build represents.
    let step: SolanaMoveStakeStep
    /// Lamports moving to B. Used by `.split` / `.redelegate`; ignored by
    /// `.deactivate` (the whole account cools down).
    let amount: String

    var sendMaxAmount: Bool { false }

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        ThreadSafeDictionary<String, String>()
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }

    /// `toAddress` doubles as the verify-screen "destination". For a move the
    /// destination validator (B) is what the user is moving their stake to.
    var toAddress: String { votePubkey }

    var solanaStakingPayload: SolanaStakingPayload? {
        switch step {
        case .deactivate:
            return SolanaStakingPayload.moveStakeDeactivate(
                movedStakeAccount: stakeAccount,
                votePubkey: votePubkey
            )
        case .redelegate:
            return SolanaStakingPayload.moveStakeRedelegate(
                movedStakeAccount: stakeAccount,
                votePubkey: votePubkey,
                lamports: lamports(from: amount)
            )
        case .split:
            return SolanaStakingPayload.moveStakeSplit(
                sourceStakeAccount: stakeAccount,
                splitStakeAccount: stakeAccount,
                votePubkey: votePubkey,
                lamports: lamports(from: amount)
            )
        }
    }

    /// Converts the human-decimal SOL amount ("0.0289…") into lamports via the
    /// shared send-path scaler (locale-aware, ×10^decimals), then clamps to the
    /// `UInt64` range. Note: this must NOT use `String.toBigInt(decimals:)`,
    /// which expects an already-scaled integer string and would truncate a
    /// fractional amount to 0 lamports.
    private func lamports(from amount: String) -> UInt64 {
        let raw = SendCryptoLogic.amountInRaw(coin: coin, amount: amount)
        guard raw > 0, raw <= BigInt(UInt64.max) else { return 0 }
        return UInt64(raw)
    }
}
