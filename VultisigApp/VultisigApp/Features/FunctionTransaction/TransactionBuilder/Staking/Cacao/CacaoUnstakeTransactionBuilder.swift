//
//  CacaoUnstakeTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import VultisigCommonData

struct CacaoUnstakeTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let bps: Int
    let amount: String = "0"
    let sendMaxAmount: Bool = false

    var memo: String {
        "POOL-:\(bps)"
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("BPS", "\(bps)")
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { "" }
}
