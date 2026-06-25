//
//  TonUnstakeTransactionBuilder.swift
//  VultisigApp
//

import VultisigCommonData

/// Builds a TON nominator-pool unstake transaction: send a small fixed amount
/// of TON to the pool contract with the text comment "w". Standard nominator
/// pools support full withdrawal only, so no amount is taken from the user —
/// the "w" message triggers the full withdrawal. Logic ported from the (now
/// DeFi-only) `FunctionCallUnstake` model.
struct TonUnstakeTransactionBuilder: TransactionBuilder {
    let coin: Coin
    /// Amount accompanying the "w" message (1 TON, mirroring the legacy
    /// FunctionCall unstake). The pool returns the staked balance separately.
    let amount: String
    let sendMaxAmount: Bool = false
    let poolAddress: String

    let memo: String = "w"

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", poolAddress)
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { poolAddress }
}
