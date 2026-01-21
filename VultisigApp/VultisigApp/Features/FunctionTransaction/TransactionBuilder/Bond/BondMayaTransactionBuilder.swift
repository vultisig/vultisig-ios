//
//  BondMayaTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import VultisigCommonData

struct BondMayaTransactionBuilder: TransactionBuilder {
    let coin: Coin

    let isBond: Bool
    let nodeAddress: String
    let selectedAsset: String
    let lpUnits: UInt64

    let amount: String = "1"
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
