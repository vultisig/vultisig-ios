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
    /// The staked TCY the sheet was showing — `availableAmount` from the unstake
    /// form. Local display context only, never signed; it exists so the Verify
    /// screen can quote the payout `basisPoints` implies rather than the memo's
    /// literal `"0"`.
    let stakedAmount: Decimal

    var amount: String { "0" }

    /// The TCY this withdrawal pays out — the memo's fraction applied to the staked
    /// position — so the Verify screen states a figure instead of "You're sending
    /// 0 TCY". See `QuotedWithdrawalPresentation`.
    ///
    /// ⚠️ **A projection, not a commitment.** `tcy-:<bps>` commits to a FRACTION
    /// applied to whatever is staked when THORChain executes it; this applies that
    /// fraction to the balance the form was showing, which is the closest an
    /// absolute figure can get. `nil` for the auto-compound (sTCY) position, whose
    /// `stakedAmount` is a receipt-share count worth more than 1 TCY each — quoting
    /// a fraction of it as "X TCY" would understate the payout.
    var withdrawDisplayAmount: Decimal? {
        guard !isAutoCompound, stakedAmount > 0, basisPoints > 0 else { return nil }
        return (stakedAmount * Decimal(basisPoints)) / Decimal(WithdrawBasisPoints.max)
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
