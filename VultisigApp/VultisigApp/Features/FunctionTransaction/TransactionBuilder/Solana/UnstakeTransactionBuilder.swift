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
    /// Delegated SOL in the account being cooled down — the figure the row was
    /// showing, in human decimals.
    let delegatedAmount: Decimal

    /// Deactivate carries no amount — the whole account cools down.
    var amount: String { "0" }
    var sendMaxAmount: Bool { false }

    var functionKind: FunctionTransactionKind? { .unstake }

    /// ⚠️ **Required, not decorative.** A deactivate instruction carries no
    /// lamports, so `amount` is the literal `"0"` and naming the operation
    /// without carrying the figure would announce "You're unstaking 0 SOL" over
    /// a whole delegation.
    ///
    /// The DELEGATED stake, not the account's total lamports: the rent-exempt
    /// reserve sits in the same account but was never staked and is not what
    /// cools down. (The withdraw builder quotes the total precisely because a
    /// withdraw takes the reserve too, and closes the account.)
    var withdrawDisplayAmount: Decimal? {
        guard delegatedAmount > 0 else { return nil }
        return delegatedAmount
    }

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
