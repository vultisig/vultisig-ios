//
//  UnbondTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/11/2025.
//

import Foundation
import VultisigCommonData

struct UnbondTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let unbondAmount: String
    let sendMaxAmount: Bool
    let nodeAddress: String
    let providerAddress: String

    var amount: String { "0" }

    var functionKind: FunctionTransactionKind? { .unbond }

    /// ⚠️ **Required, not decorative.** An UNBOND is a memo-only `MsgDeposit`:
    /// `amount` is the literal `"0"` and the figure being unbonded rides in the
    /// memo as base units. Naming the operation without carrying the figure
    /// would turn "You're sending 0 RUNE" into "You're unbonding 0 RUNE" — a
    /// better verb over the same wrong number.
    var withdrawDisplayAmount: Decimal? {
        let unbonded = unbondAmount.toDecimal()
        guard unbonded > 0 else { return nil }
        return unbonded
    }

    var amountInUnits: String {
        let amountInSats = coin.decimalToCrypto(value: unbondAmount.toDecimal())
        return amountInSats.description
    }

    var memo: String {
        var memo = "UNBOND:\(nodeAddress):\(amountInUnits)"
        if providerAddress.isNotEmpty {
            memo += ":\(providerAddress)"
        }
        return memo
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", nodeAddress)
        dict.set("Unbond amount", "\(unbondAmount)")
        dict.set("provider", providerAddress)
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { "" }
}
