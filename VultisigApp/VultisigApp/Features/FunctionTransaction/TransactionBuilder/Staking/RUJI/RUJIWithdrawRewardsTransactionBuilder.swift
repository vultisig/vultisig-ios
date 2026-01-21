//
//  RUJIWithdrawRewardsTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/11/2025.
//

import Foundation
import VultisigCommonData

struct RUJIWithdrawRewardsTransactionBuilder: TransactionBuilder {
    static let destinationAddress = RUJIStakingConstants.contract
    let coin: Coin
    let withdrawAmount: String
    let sendMaxAmount: Bool
    let amount: String = "0"

    var rawAmount: String {
        coin.decimalToCrypto(value: withdrawAmount.toDecimal()).description
    }

    var memo: String {
        return "claim:\(coin.contractAddress):\(rawAmount)"
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
            { "account": { "claim": {} } }
            """,
            coins: []
        )
    }
    var toAddress: String { Self.destinationAddress }
}
