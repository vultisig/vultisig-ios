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
    /// `tcy-:<bps>` memo carries. See `TCYUnstakeBasisPoints` for why it is not a
    /// percentage: routing it through one spent 100 of the memo's 10 000 steps
    /// and floored a request for 1002.73 TCY down to 1001.37.
    let basisPoints: Int
    let autoCompoundAmount: Decimal
    let sendMaxAmount: Bool
    let isAutoCompound: Bool
    /// The position this withdrawal is a fraction of — the balance the sheet was
    /// showing. `basisPoints` of it is what the chain will pay out, and what the
    /// screens around signing quote.
    let stakedAmount: Decimal

    var amount: String { "0" }

    /// The figure the verify screen announces, quantised to `basisPoints`.
    ///
    /// Deliberately NOT the amount that was typed. The withdrawal can only ask
    /// for ten-thousandths of the position, so the typed figure and the delivered
    /// one differ by up to one basis point — and quoting the typed one would be
    /// the same class of lie as the "You're sending 0 TCY" this replaces, just a
    /// smaller one.
    ///
    /// True on the auto-compound (sTCY) branch too, even though that one spends
    /// receipt units through a wasm payload rather than the memo: the sheet's
    /// ceiling for TCY *is* the receipt balance (`receiptBalanceIsAvailableAmount`),
    /// so `stakedAmount` and `autoCompoundAmount` are the same quantity and the
    /// same fraction of it is taken either way.
    var withdrawDisplayAmount: Decimal? {
        guard stakedAmount > 0, basisPoints > 0 else { return nil }
        return (stakedAmount * Decimal(basisPoints)) / Decimal(TCYUnstakeBasisPoints.max)
    }

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
            / Decimal(TCYUnstakeBasisPoints.max)
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
