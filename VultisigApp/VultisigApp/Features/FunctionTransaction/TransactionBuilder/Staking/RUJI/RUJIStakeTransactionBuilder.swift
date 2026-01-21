//
//  RUJIStakeTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/11/2025.
//

import Foundation
import VultisigCommonData

struct RUJIStakeTransactionBuilder: TransactionBuilder {
    static let destinationAddress = RUJIStakingConstants.contract
    let coin: Coin
    let amount: String
    let sendMaxAmount: Bool

    var rawAmount: String {
        coin.decimalToCrypto(value: amount.toDecimal()).description
    }

    var memo: String {
        "bond:\(coin.contractAddress):\(rawAmount)"
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType {
        .genericContract
    }

    var wasmContractPayload: WasmExecuteContractPayload? {
        WasmExecuteContractPayload(
            senderAddress: coin.address,
            contractAddress: Self.destinationAddress,
            executeMsg: """
            { "account": { "bond": {} } }
            """,
            coins: [CosmosCoin(
                amount: rawAmount,
                denom: coin.contractAddress
            )]
        )
    }
    var toAddress: String { Self.destinationAddress }
}
