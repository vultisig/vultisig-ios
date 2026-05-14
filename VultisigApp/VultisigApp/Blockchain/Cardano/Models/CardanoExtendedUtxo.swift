//
//  CardanoExtendedUtxo.swift
//  VultisigApp
//

import BigInt
import Foundation

struct CardanoUtxoAsset: Hashable, Codable {
    let policyId: String
    let assetNameHex: String
    let amount: BigInt
    let decimals: Int

    enum CodingKeys: String, CodingKey {
        case policyId, assetNameHex, amount, decimals
    }

    init(policyId: String, assetNameHex: String, amount: BigInt, decimals: Int) {
        self.policyId = policyId
        self.assetNameHex = assetNameHex
        self.amount = amount
        self.decimals = decimals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.policyId = try container.decode(String.self, forKey: .policyId)
        self.assetNameHex = try container.decode(String.self, forKey: .assetNameHex)
        let amountString = try container.decode(String.self, forKey: .amount)
        guard let amount = BigInt(amountString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .amount,
                in: container,
                debugDescription: "Cannot parse BigInt from \(amountString)"
            )
        }
        self.amount = amount
        self.decimals = try container.decodeIfPresent(Int.self, forKey: .decimals) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(policyId, forKey: .policyId)
        try container.encode(assetNameHex, forKey: .assetNameHex)
        try container.encode(amount.description, forKey: .amount)
        try container.encode(decimals, forKey: .decimals)
    }
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

        let rawAssets = entry.assetList ?? []
        let assets: [CardanoUtxoAsset] = rawAssets.compactMap { asset in
            guard let quantity = BigInt(asset.quantity), quantity >= 0 else { return nil }
            let decimals = asset.decimals ?? 0
            // Negative decimals would leak invalid precision into downstream
            // amount formatting. Fail-fast on the whole UTxO, consistent with
            // the rest of this parser.
            guard decimals >= 0 else { return nil }
            return CardanoUtxoAsset(
                policyId: asset.policyId.lowercased(),
                assetNameHex: (asset.assetName ?? "").lowercased(),
                amount: quantity,
                decimals: decimals
            )
        }
        // If any asset failed to parse, reject the whole UTxO — using a
        // partially-decoded UTxO at sign time would understate the token
        // bundle and produce an invalid Cardano body.
        guard assets.count == rawAssets.count else { return nil }

        self.init(hash: entry.txHash, index: index, amount: amount, assets: assets)
    }
}
