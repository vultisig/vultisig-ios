//
//  RemoveLPTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/11/2025.
//

import Foundation
import VultisigCommonData

struct RemoveLPTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let amount: String
    let poolName: String
    let poolUnits: String
    let percentage: Double
    let sendMaxAmount: Bool

    var memo: String {
        let basisPoints = percentage * 100
        let lpData = RemoveLPMemoData(pool: poolName, basisPoints: Int(basisPoints))
        return lpData.memo
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("pool", poolName)
        dict.set("withdrawPercentage", "\(percentage)%")
        dict.set("units", poolUnits)
        if coin.chain == .thorChain {
            dict.set("dustAmount", "0.02 RUNE")
        }
        dict.set("memo", memo)
        return dict
    }

    /// ⚠️ **Deliberately unnamed.** `amount` is the 0.02 RUNE dust a THORChain
    /// withdrawal has to attach (zero on MAYAChain), not the liquidity being
    /// removed — that is `percentage` of a two-sided pool position, which no
    /// single-coin hero can state. "You're removing liquidity 0.02 RUNE" would
    /// misname the dust as the withdrawal, and the hero would also drop the
    /// "→ <pool> LP" the generic header currently carries.
    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { .empty }
}
