//
//  RUJIUnstakeTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/11/2025.
//

import Foundation
import VultisigCommonData

struct RUJIUnstakeTransactionBuilder: TransactionBuilder {
    static let destinationAddress = RUJIStakingConstants.contract
    let coin: Coin
    let amount: String
    let sendMaxAmount: Bool

    var rawAmount: String {
        coin.decimalToCrypto(value: amount.toDecimal()).description
    }

    /// The RUJI this bonded withdrawal pays out. Unlike the fractional TCY memo,
    /// `account.withdraw` carries an ABSOLUTE amount (`withdraw:<contract>:<raw>`),
    /// so this is exact — the figure the user typed — not a projection. `amount`
    /// the protocol requirement is the typed value here, but the Verify hero reads
    /// what will be signed, so it is surfaced explicitly. See
    /// `QuotedWithdrawalPresentation`.
    var withdrawDisplayAmount: Decimal? {
        let value = amount.toDecimal()
        return value > 0 ? value : nil
    }

    var memo: String {
        "withdraw:\(coin.contractAddress):\(rawAmount)"
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
            { "account": { "withdraw": { "amount": "\(rawAmount)" } } }
            """,
            coins: []
        )
    }
    var toAddress: String { Self.destinationAddress }
}
