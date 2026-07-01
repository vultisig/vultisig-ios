//
//  DelegateTransactionBuilder.swift
//  VultisigApp
//
//  Per-flow builder for a Solana native-staking delegate. A pure value-type
//  carrier; the unsigned transaction bytes are produced lazily by
//  `SolanaStakingSignDataResolver.resolve(...)` at Verify → KeysignPayload
//  bridge time so the recent blockhash is always fresh. Analog of
//  `CosmosDelegateTransactionBuilder`.
//
//  `memo = ""`, `transactionType = .unspecified` — the real intent travels via
//  the `solanaStakingPayload` accessor.
//

import BigInt
import Foundation
import VultisigCommonData

struct SolanaDelegateTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let amount: String
    let sendMaxAmount: Bool
    let votePubkey: String

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        ThreadSafeDictionary<String, String>()
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }

    /// `toAddress` doubles as the verify-screen "destination" — for a delegate
    /// the validator vote account is what the user is staking to.
    var toAddress: String { votePubkey }

    var solanaStakingPayload: SolanaStakingPayload? {
        let lamports = lamports(from: amount)
        return SolanaStakingPayload.delegate(votePubkey: votePubkey, lamports: lamports)
    }

    /// Converts the human-decimal SOL amount ("0.0289…") into lamports via the
    /// shared send-path scaler (locale-aware, ×10^decimals), then clamps to the
    /// `UInt64` range the wallet-core stake proto expects. Note: this must NOT
    /// use `String.toBigInt(decimals:)`, which expects an already-scaled integer
    /// string and would truncate a fractional amount to 0 lamports.
    private func lamports(from amount: String) -> UInt64 {
        let raw = SendCryptoLogic.amountInRaw(coin: coin, amount: amount)
        guard raw > 0, raw <= BigInt(UInt64.max) else { return 0 }
        return UInt64(raw)
    }
}
