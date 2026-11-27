//
//  BondYieldTransactionBuilder.swift
//  VultisigApp
//

import Foundation
import VultisigCommonData

/// THORChain Rewards Payout: the share of a node's future bond rewards paid out
/// to the vault's own address; the rest is rebonded.
struct BondYieldTransactionBuilder: TransactionBuilder {
    static let basisPointsPerPercent = 100

    let coin: Coin
    let nodeAddress: String
    let payoutPercentage: Int

    init?(coin: Coin, nodeAddress: String, payoutPercentage: Int) {
        guard (0...100).contains(payoutPercentage) else { return nil }
        self.coin = coin
        self.nodeAddress = nodeAddress
        self.payoutPercentage = payoutPercentage
    }

    var amount: String { "0" }
    var sendMaxAmount: Bool { false }

    // With a non-zero share and no target, THORChain keeps paying whatever
    // target was stored before, so the vault address is always written out.
    var memo: String {
        guard payoutPercentage > 0 else { return "BONDYIELD:\(nodeAddress):0" }
        return "BONDYIELD:\(nodeAddress):\(payoutPercentage * Self.basisPointsPerPercent):\(coin.address)"
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", nodeAddress)
        dict.set("payoutPercentage", "\(payoutPercentage)%")
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { "" }
}
