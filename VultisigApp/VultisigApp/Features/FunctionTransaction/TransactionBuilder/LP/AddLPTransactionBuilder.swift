//
//  AddLPTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/11/2025.
//

import Foundation
import VultisigCommonData

struct AddLPTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let amount: String
    let poolName: String
    let pairedAddress: String?
    let sendMaxAmount: Bool

    var amountMicro: UInt64 {
        let decimals = coin.decimals
        let multiplier = pow(10.0, Double(decimals))
        let micro = (amount.toDecimal() * Decimal(multiplier)) as NSDecimalNumber
        return micro.uint64Value
    }

    var memo: String {
        let address = pairedAddress?.nilIfEmpty
        let lpData = AddLPMemoData(pool: poolName, pairedAddress: address)
        return lpData.memo
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("pool", poolName)
        if let pairedAddress {
            dict.set("pairedAddress", pairedAddress)
        }
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType {
        .unspecified
    }

    var wasmContractPayload: WasmExecuteContractPayload? {
        nil
    }

    var toAddress: String {
        // For addThorLP, return the inbound address that was set by fetchInboundAddress()
        // This is essential for Bitcoin and other chains to know where to send funds
        return .empty
    }
}
