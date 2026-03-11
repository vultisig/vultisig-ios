//
//  CardanoResponse.swift
//  VultisigApp
//

import Foundation

/// Koios API /address_info response — array decoded as top-level wrapper
struct CardanoAddressInfoResponse: Codable {
    let addresses: [CardanoAddressInfo]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        addresses = try container.decode([CardanoAddressInfo].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(addresses)
    }
}

struct CardanoAddressInfo: Codable {
    let address: String
    let balance: String
    let utxoSet: [CardanoUTXO]

    enum CodingKeys: String, CodingKey {
        case address, balance
        case utxoSet = "utxo_set"
    }
}

struct CardanoUTXO: Codable {
    let value: String
    let txHash: String
    let txIndex: Int
    let assetList: [CardanoAsset]

    enum CodingKeys: String, CodingKey {
        case value
        case txHash = "tx_hash"
        case txIndex = "tx_index"
        case assetList = "asset_list"
    }
}

struct CardanoAsset: Codable {
    let quantity: String
    let policyId: String
    let assetName: String

    enum CodingKeys: String, CodingKey {
        case quantity
        case policyId = "policy_id"
        case assetName = "asset_name"
    }
}

/// Koios API /tip response
struct CardanoTipResponse: Codable {
    let tips: [CardanoTip]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        tips = try container.decode([CardanoTip].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(tips)
    }
}

struct CardanoTip: Codable {
    let absSlot: UInt64

    enum CodingKeys: String, CodingKey {
        case absSlot = "abs_slot"
    }
}

/// Vultisig API Proxy JSON-RPC broadcast response
struct CardanoBroadcastResponse: Codable {
    let result: CardanoBroadcastResult?
    let error: CardanoBroadcastRPCError?
}

struct CardanoBroadcastResult: Codable {
    let transaction: CardanoBroadcastTransaction
}

struct CardanoBroadcastTransaction: Codable {
    let id: String
}

struct CardanoBroadcastRPCError: Codable {
    let code: Int
    let message: String
}
