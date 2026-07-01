//
//  UnstakeTransactionBuilder.swift
//  VultisigApp
//
//  Per-flow builder for a Solana native-staking deactivate (unstake). A pure
//  value-type carrier; the unsigned transaction bytes are produced lazily by
//  `SolanaStakingSignDataResolver.resolveDeactivate(...)` at Verify →
//  KeysignPayload bridge time so the recent blockhash is always fresh. Analog
//  of `SolanaDelegateTransactionBuilder` / `CosmosUndelegateTransactionBuilder`.
//
//  Deactivate carries no amount — the whole stake account cools down — so the
//  staking payload only needs the source stake account address.
//

import BigInt
import Foundation
import VultisigCommonData

struct SolanaUnstakeTransactionBuilder: TransactionBuilder {
    let coin: Coin
    /// Source stake account being deactivated (its own pubkey, not the owner's).
    let stakeAccount: String

    /// Deactivate carries no amount — the whole account cools down.
    var amount: String { "0" }
    var sendMaxAmount: Bool { false }

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        ThreadSafeDictionary<String, String>()
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }

    /// `toAddress` doubles as the verify-screen "destination" — for a deactivate
    /// the stake account being cooled down is what the user is acting on.
    var toAddress: String { stakeAccount }

    var solanaStakingPayload: SolanaStakingPayload? {
        SolanaStakingPayload.unstake(stakeAccount: stakeAccount)
    }
}
