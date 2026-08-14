//
//  TCYStakeTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/11/2025.
//

import VultisigCommonData

struct TCYStakeTransactionBuilder: TransactionBuilder {
    static let destinationAddress = TCYAutoCompoundConstants.contract
    let coin: Coin
    let amount: String
    let sendMaxAmount: Bool
    let isAutoCompound: Bool

    var rawAmount: String {
        coin.decimalToCrypto(value: amount.toDecimal()).description
    }

    var memo: String {
        "tcy+"
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType {
        isAutoCompound ? .genericContract : .unspecified
    }

    var wasmContractPayload: WasmExecuteContractPayload? {
        guard isAutoCompound else { return nil }

        return WasmExecuteContractPayload(
            senderAddress: coin.address,
            contractAddress: Self.destinationAddress,
            executeMsg: """
            { "liquid": { "bond": {} } }
            """,
            coins: [CosmosCoin(
                amount: rawAmount,
                denom: coin.contractAddress
            )]
        )
    }

    var toAddress: String { "" }
}
