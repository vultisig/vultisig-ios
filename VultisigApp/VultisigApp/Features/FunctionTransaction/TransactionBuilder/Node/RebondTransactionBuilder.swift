//
//  RebondTransactionBuilder.swift
//  VultisigApp
//
//  THORChain node REBOND: move a bond from the validator that holds it to
//  another one. Two addresses, an optional partial amount that travels in the
//  memo, and nothing attached to the transaction itself.
//

import Foundation
import VultisigCommonData

struct RebondTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let currentNodeAddress: String
    let newNodeAddress: String
    /// Zero means "the whole bond": the memo then carries no amount segment
    /// and the protocol moves everything bonded to `currentNodeAddress`.
    let rebondAmount: Decimal

    /// REBOND moves no value through this transaction — the bond never leaves
    /// the protocol, only the validator holding it changes, and the amount
    /// rides the memo. Pinned to the legacy sub-model's zero: RUNE attached to
    /// this `MsgDeposit` has no return path, so it is a fund-safety constant,
    /// not a default.
    let amount: String = "0"
    let sendMaxAmount: Bool = false

    /// THORChain node-operation memos denominate amounts in fixed 1e8 base
    /// units — the exponent the legacy sub-model applied, independent of
    /// `coin.decimals`. `int64Value` on the scaled `NSDecimalNumber`
    /// truncates, so anything under one base unit scales to zero; the form's
    /// amount validator rejects such an input before it can reach here.
    static func memoUnits(from amount: Decimal) -> Int64 {
        NSDecimalNumber(decimal: amount)
            .multiplying(byPowerOf10: 8)
            .int64Value
    }

    var memo: String {
        var memo = "REBOND:\(currentNodeAddress):\(newNodeAddress)"
        // Gated on the decimal, not on the scaled integer, exactly as the
        // legacy sub-model was. An amount that truncates to zero therefore
        // still emits `:0` — a rebond of nothing — rather than falling through
        // to the whole-bond shape, which would move the entire stake.
        if rebondAmount > 0 {
            memo += ":\(Self.memoUnits(from: rebondAmount))"
        }
        return memo
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", currentNodeAddress)
        dict.set("newAddress", newNodeAddress)
        if rebondAmount > 0 {
            dict.set("rebondAmount", "\(rebondAmount)")
        }
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// Empty: a `MsgDeposit` is addressed by its memo, not by a recipient.
    var toAddress: String { .empty }
}
