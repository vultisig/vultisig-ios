//
//  LeaveTransactionBuilder.swift
//  VultisigApp
//
//  THORChain / MayaChain node LEAVE. One field (the node address), one memo,
//  nothing attached.
//

import VultisigCommonData

struct LeaveTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let nodeAddress: String

    /// LEAVE moves no value. The node leaves the active set on the memo alone
    /// and the protocol returns its bond over the following churns — this
    /// transaction is the request, not the transfer. Pinned to the legacy
    /// sub-model's zero: RUNE / CACAO attached to a `MsgDeposit` that has no
    /// return path is burnt, so this is a fund-safety constant, not a default.
    let amount: String = "0"
    let sendMaxAmount: Bool = false

    var memo: String { "LEAVE:\(nodeAddress)" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", nodeAddress)
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// Empty: a `MsgDeposit` is addressed by its memo, not by a recipient.
    var toAddress: String { .empty }
}
