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

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { "" }
}
