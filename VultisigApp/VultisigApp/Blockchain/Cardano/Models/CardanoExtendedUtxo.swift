//
//  CardanoExtendedUtxo.swift
//  VultisigApp
//

import BigInt
import Foundation

struct CardanoUtxoAsset: Hashable {
    let policyId: String
    let assetNameHex: String
    let amount: BigInt
    let decimals: Int
}

struct CardanoExtendedUtxo: Hashable {
    let hash: String
    let index: UInt32
    let amount: UInt64
    let assets: [CardanoUtxoAsset]

    var hasAssets: Bool { !assets.isEmpty }
}

extension CardanoExtendedUtxo {
    init?(_ entry: CardanoExtendedUtxoEntry) {
        guard
            let amount = UInt64(entry.value),
            let index = UInt32(exactly: entry.txIndex),
            !entry.txHash.isEmpty
        else { return nil }

        let assets: [CardanoUtxoAsset] = (entry.assetList ?? []).compactMap { asset in
            guard let quantity = BigInt(asset.quantity) else { return nil }
            return CardanoUtxoAsset(
                policyId: asset.policyId.lowercased(),
                assetNameHex: (asset.assetName ?? "").lowercased(),
                amount: quantity,
                decimals: asset.decimals ?? 0
            )
        }

        self.init(hash: entry.txHash, index: index, amount: amount, assets: assets)
    }
}
