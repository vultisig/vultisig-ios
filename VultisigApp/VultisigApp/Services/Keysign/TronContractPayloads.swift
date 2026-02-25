//
//  TronContractPayloads.swift
//  VultisigApp
//
//  Created for Tron dApp integration
//

import Foundation

// MARK: - Tron Contract Payloads

/// Payload for native TRX transfers via dApp
struct TronTransferContractPayload: Codable, Hashable {
    let toAddress: String
    let ownerAddress: String
    let amount: String

    enum CodingKeys: String, CodingKey {
        case toAddress = "to_address"
        case ownerAddress = "owner_address"
        case amount
    }
}

/// Payload for smart contract execution (dApp interactions)
struct TronTriggerSmartContractPayload: Codable, Hashable {
    let ownerAddress: String
    let contractAddress: String
    let callValue: String?
    let callTokenValue: String?
    let tokenId: Int32?
    let data: String?

    enum CodingKeys: String, CodingKey {
        case ownerAddress = "owner_address"
        case contractAddress = "contract_address"
        case callValue = "call_value"
        case callTokenValue = "call_token_value"
        case tokenId = "token_id"
        case data
    }
}

/// Payload for TRC-20 asset transfers via dApp
struct TronTransferAssetContractPayload: Codable, Hashable {
    let toAddress: String
    let ownerAddress: String
    let amount: String
    let assetName: String

    enum CodingKeys: String, CodingKey {
        case toAddress = "to_address"
        case ownerAddress = "owner_address"
        case amount
        case assetName = "asset_name"
    }
}
