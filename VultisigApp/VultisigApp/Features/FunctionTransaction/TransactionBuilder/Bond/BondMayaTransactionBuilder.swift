//
//  BondMayaTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import Foundation
import VultisigCommonData

struct BondMayaTransactionBuilder: TransactionBuilder {
    /// CACAO attached to a BOND.
    private static let bondCacao: Decimal = 1

    let coin: Coin

    let isBond: Bool
    let nodeAddress: String
    let selectedAsset: String
    let lpUnits: UInt64

    /// Dust attached to an UNBOND: exactly one base unit.
    ///
    /// The amount being unbonded travels in the memo's LPUNITS field, so the
    /// transfer itself only has to be non-zero for the node to pick the memo
    /// up — the smallest value the coin can express is enough. Matches what
    /// Android and Windows send.
    ///
    /// Derived from the coin's own decimals rather than written as a literal,
    /// because this is a HUMAN decimal that `SendCryptoLogic.amountInRaw`
    /// multiplies back by `10^decimals`. A hardcoded exponent is only "one base
    /// unit" for one particular `decimals` value, and silently becomes a
    /// multiple of it for any other — a `1e-8` literal was 100 base units on
    /// CACAO's 10 decimals, not one.
    ///
    /// Exact for `decimals` in 0...18, measured. Above 18 the round trip is
    /// erratic — 24, 36 and 40 collapse to zero while 30 and 38 survive —
    /// because `NumberFormatter` loses the value re-parsing that many fraction
    /// digits, not because `Decimal` underflows. 18 is the ceiling for every
    /// coin this app carries (EVM's maximum; CACAO is 10), and this builder
    /// only ever sees MayaChain CACAO, so the erratic range is unreachable. No
    /// clamp: silently signing a *different* amount would be worse than the
    /// range being impossible to reach.
    private var unbondDust: Decimal {
        1 / pow(10, coin.decimals)
    }

    /// The two directions attach different amounts. Emitting the bond's `1` for
    /// an unbond signs a whole CACAO where one base unit is meant — on CACAO's
    /// 10 decimals, 10^10 times the intended dust.
    var amount: String {
        (isBond ? Self.bondCacao : unbondDust)
            .formatToDecimal(digits: coin.decimals)
    }

    let sendMaxAmount: Bool = false

    var prefix: String {
        isBond ? "BOND" : "UNBOND"
    }

    var memo: String {
        "\(prefix):\(selectedAsset):\(lpUnits):\(nodeAddress)"
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("asset", selectedAsset)
        dict.set("LPUNITS", "\(lpUnits)")
        dict.set("nodeAddress", nodeAddress)
        dict.set("memo", memo)
        return dict
    }

    /// ⚠️ **Deliberately unnamed.** `amount` here is a fixed 1 CACAO carrier,
    /// not the size of the bond — what is actually bonded (or unbonded) is
    /// `lpUnits` of `selectedAsset`, and it rides in the memo. "You're sending 1
    /// CACAO" is at least true; "You're bonding 1 CACAO" would not be. Naming
    /// this operation needs a figure the hero can state in the coin's own
    /// denomination, which an LP-unit bond does not have.
    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { "" }
}
