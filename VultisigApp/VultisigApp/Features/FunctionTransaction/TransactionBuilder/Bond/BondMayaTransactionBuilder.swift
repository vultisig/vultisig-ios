//
//  BondMayaTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import Foundation
import VultisigCommonData

struct BondMayaTransactionBuilder: TransactionBuilder {
    /// Fixed dust attached to an UNBOND, in CACAO. The bonded amount travels in
    /// the memo's LPUNITS field, so the transfer itself only has to be non-zero
    /// for the node to pick the memo up.
    private static let unbondDustCacao: Decimal = 1 / pow(10, 8)

    /// CACAO attached to a BOND.
    private static let bondCacao: Decimal = 1

    let coin: Coin

    let isBond: Bool
    let nodeAddress: String
    let selectedAsset: String
    let lpUnits: UInt64

    /// The two directions attach different amounts, and this string is a HUMAN
    /// decimal — `SendCryptoLogic.amountInRaw` multiplies it by `10^decimals`
    /// to get what is signed. Emitting the bond's `1` for an unbond too signs a
    /// whole CACAO where 1e-8 is meant, which for CACAO's 10 decimals is 10^8
    /// times the intended dust.
    var amount: String {
        (isBond ? Self.bondCacao : Self.unbondDustCacao)
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
