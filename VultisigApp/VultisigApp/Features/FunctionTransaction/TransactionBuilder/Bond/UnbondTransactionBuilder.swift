//
//  UnbondTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/11/2025.
//

import Foundation
import VultisigCommonData

struct UnbondTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let unbondAmount: String
    let sendMaxAmount: Bool
    let nodeAddress: String
    let providerAddress: String

    var amount: String { "0" }

    var amountInUnits: String {
        let amountInSats = coin.decimalToCrypto(value: unbondAmount.toDecimal())
        return amountInSats.description
    }

    var memo: String {
        var memo = "UNBOND:\(nodeAddress):\(amountInUnits)"
        if providerAddress.isNotEmpty {
            memo += ":\(providerAddress)"
        }
        return memo
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", nodeAddress)
        dict.set("Unbond amount", "\(unbondAmount)")
        dict.set("provider", providerAddress)
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { "" }
}
