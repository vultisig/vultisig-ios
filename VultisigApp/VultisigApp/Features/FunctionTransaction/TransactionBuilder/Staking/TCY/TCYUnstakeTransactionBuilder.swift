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
    /// The position this withdrawal is a fraction of — the balance the sheet was
    /// showing. `basisPoints` of it is what the chain will pay out, and what the
    /// screens around signing quote.
    let stakedAmount: Decimal

    var amount: String { "0" }

    var functionKind: FunctionTransactionKind? { .unstake }

    /// The figure the verify screen announces, quantised to `basisPoints`.
    ///
    /// Deliberately NOT the amount that was typed. The withdrawal can only ask
    /// for ten-thousandths of the position, so the typed figure and the delivered
    /// one differ by up to one basis point — and quoting the typed one would be
    /// the same class of lie as the "You're sending 0 TCY" this replaces, just a
    /// smaller one.
    ///
    /// ⚠️ **It is a projection, not a commitment.** The memo commits to a
    /// FRACTION, applied to whatever is staked when THORChain executes it; this
    /// figure applies that fraction to the balance the form was showing. If the
    /// position changes in between — rewards landing, or another device staking —
    /// the payout moves with it. Quoting the balance the user was just looking at
    /// is the closest an absolute figure can get, and it is what the issue asks
    /// the screen to show; naming the fraction instead would be exact but would
    /// not answer "did it take the number I typed".
    ///
    /// ⚠️ **Nil for the auto-compound (sTCY) position**, which is share-based.
    /// There, `stakedAmount` is a count of `x/staking-tcy` receipt shares, not
    /// TCY: `liquid.unbond` burns shares and returns the pool principal they are
    /// worth, and a share is worth more than 1 TCY and drifts further as revenue
    /// compounds (`fetchTcyAutoCompoundAmount` is the same share read that
    /// `fetchRujiStakingReceiptAmount` documents as "not a display value").
    /// Quoting a fraction of the share count as "X TCY" would understate the
    /// payout on the screen where it is approved. Naming no figure is worse copy
    /// than naming one, but it is not a wrong number, and pricing shares
    /// correctly means resolving the live redemption ratio — a different change
    /// on a position this issue does not cover.
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
