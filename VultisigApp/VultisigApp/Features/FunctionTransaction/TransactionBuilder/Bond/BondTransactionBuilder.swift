//
//  BondTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/11/2025.
//

import VultisigCommonData

struct BondTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let amount: String
    let sendMaxAmount: Bool
    let nodeAddress: String
    let providerAddress: String
    let operatorFee: Int64?

    var memo: String {
        var memo = "BOND:\(nodeAddress)"
        if !providerAddress.isEmpty {
            memo += ":\(providerAddress)"
        }
        if let operatorFee, operatorFee != .zero {
            if providerAddress.isEmpty {
                memo += "::\(operatorFee)"
            } else {
                memo += ":\(operatorFee)"
            }
        }
        return memo
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", nodeAddress)
        dict.set("provider", providerAddress)
        dict.set("fee", "\(operatorFee ?? 0)")
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { "" }
}
