//
//  TransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/11/2025.
//

import VultisigCommonData

protocol TransactionBuilder {
    var coin: Coin { get }
    var amount: String { get }
    var sendMaxAmount: Bool { get }
    var memo: String { get }
    var memoFunctionDictionary: ThreadSafeDictionary<String, String> { get }
    var transactionType: VSTransactionType { get }
    var wasmContractPayload: WasmExecuteContractPayload? { get }
    var toAddress: String { get }
}

extension TransactionBuilder {
    func buildTransaction() -> SendTransaction {
        let sendTx = SendTransaction()
        sendTx.fromAddress = coin.address
        sendTx.coin = coin
        sendTx.amount = amount
        sendTx.memo = memo
        sendTx.memoFunctionDictionary = memoFunctionDictionary
        sendTx.transactionType = transactionType
        sendTx.wasmContractPayload = wasmContractPayload
        sendTx.toAddress = toAddress

        return sendTx
    }
}
