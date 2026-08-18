//
//  TCYUnstakeTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/11/2025.
//

import Foundation
import VultisigCommonData

struct TCYUnstakeTransactionBuilder: TransactionBuilder {
    static let destinationAddress = TCYAutoCompoundConstants.contract
    let coin: Coin
    /// The share of the position to withdraw, in ten-thousandths — the unit the
    /// `tcy-:<bps>` memo carries. See `WithdrawBasisPoints` for why it is not a
    /// percentage: routing it through one spent 100 of the memo's 10 000 steps
    /// and floored a request for 1002.73 TCY down to 1001.37.
    let basisPoints: Int
    let autoCompoundAmount: Decimal
    let sendMaxAmount: Bool
    let isAutoCompound: Bool

    var amount: String { "0" }

    var memo: String {
        if !isAutoCompound {
            return "tcy-:\(basisPoints)"
        }
        return ""
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

        let withdrawAmount = (coin.decimalToCrypto(value: autoCompoundAmount) * Decimal(basisPoints))
            / Decimal(WithdrawBasisPoints.max)
        let units = withdrawAmount.toInt()
        guard units >= 1 else { return nil }

        return WasmExecuteContractPayload(
            senderAddress: coin.address,
            contractAddress: Self.destinationAddress,
            executeMsg: """
            { "liquid": { "unbond": {} } }
            """,
            coins: [CosmosCoin(
                amount: String(units),
                denom: "x/staking-tcy"
            )]
        )
    }

    var toAddress: String { "" }
}
