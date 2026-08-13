//
//  CacaoUnstakeTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import Foundation
import VultisigCommonData

struct CacaoUnstakeTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let bps: Int
    /// The position this withdrawal is a fraction of — the balance the sheet was
    /// showing. `bps` of it is what MAYAChain will pay out, and what the screens
    /// around signing quote.
    let stakedAmount: Decimal
    let amount: String = "0"
    let sendMaxAmount: Bool = false

    var functionKind: FunctionTransactionKind? { .unstake }

    /// The figure the verify screen announces, quantised to `bps`.
    ///
    /// ⚠️ **Required, not decorative.** `POOL-:<bps>` is a memo-only deposit:
    /// `amount` is the literal `"0"`, so without this the screen would announce
    /// a withdrawal of zero CACAO — the identical defect the TCY side exists to
    /// fix, on MAYAChain instead of THORChain.
    ///
    /// Deliberately NOT the amount that was typed: the memo can only ask for
    /// ten-thousandths of the position, so the typed figure and the delivered one
    /// differ by up to one basis point. It is a projection, not a commitment —
    /// the memo commits to a FRACTION applied to whatever is staked when the
    /// chain executes it, and this applies that fraction to the balance the form
    /// was showing. See `TCYUnstakeTransactionBuilder.withdrawDisplayAmount`.
    var withdrawDisplayAmount: Decimal? {
        guard stakedAmount > 0, bps > 0 else { return nil }
        return (stakedAmount * Decimal(bps)) / Decimal(WithdrawBasisPoints.max)
    }

    var memo: String {
        "POOL-:\(bps)"
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("BPS", "\(bps)")
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { "" }
}
