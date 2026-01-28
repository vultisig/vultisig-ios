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

/// Payload for freezing TRX to gain bandwidth/energy (Stake 2.0)
struct TronFreezeBalanceV2Payload: Codable, Hashable {
    let ownerAddress: String
    let frozenBalance: String  // Amount in SUN (1 TRX = 1,000,000 SUN)
    let resource: String       // "BANDWIDTH" or "ENERGY"

    enum CodingKeys: String, CodingKey {
        case ownerAddress = "owner_address"
        case frozenBalance = "frozen_balance"
        case resource
    }
}

/// Payload for unfreezing TRX (Stake 2.0)
struct TronUnfreezeBalanceV2Payload: Codable, Hashable {
    let ownerAddress: String
    let unfreezeBalance: String  // Amount in SUN (1 TRX = 1,000,000 SUN)
    let resource: String          // "BANDWIDTH" or "ENERGY"

    enum CodingKeys: String, CodingKey {
        case ownerAddress = "owner_address"
        case unfreezeBalance = "unfreeze_balance"
        case resource
    }
}
