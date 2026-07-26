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

    /// Bonded amount in whole base units of `x/ruji`. Rounds DOWN: the amount
    /// field does not cap to the coin's 8 dp, and `CosmosCoin.amount` must be an
    /// integer base-unit string or the execute is malformed. Never round up —
    /// funding more base units than held would fail on-chain.
    var rawAmount: String {
        String(coin.decimalToCrypto(value: amount.toDecimal()).toInt())
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
        // Sub-base-unit dust truncates to zero, which the amount validator lets
        // through (it only rejects an exact zero). Bonding zero funds is a no-op
        // that still costs a fee, so refuse to build it.
        guard rawAmount != "0" else { return nil }

        return WasmExecuteContractPayload(
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
