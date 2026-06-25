//
//  TonStakeTransactionBuilder.swift
//  VultisigApp
//

import VultisigCommonData

/// Builds a TON nominator-pool stake transaction: send `amount` TON to the pool
/// contract with the text comment "d". Logic ported from the (now DeFi-only)
/// `FunctionCallStake` model.
struct TonStakeTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let amount: String
    let sendMaxAmount: Bool = false
    let poolAddress: String

    let memo: String = "d"

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
