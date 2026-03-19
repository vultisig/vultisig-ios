//
//  ThorchainLP.swift
//  VultisigApp
//

import Foundation
import BigInt

// Structure to represent a THORChain liquidity pool
struct ThorchainPool: Codable {
    let asset: String
    let status: String
    let balanceAsset: String
    let balanceRune: String
    let poolUnits: String
    let lpUnits: String
    let synthUnits: String
    let synthSupply: String
    let pendingInboundAsset: String
    let pendingInboundRune: String

    enum CodingKeys: String, CodingKey {
        case asset
        case status
        case balanceAsset = "balance_asset"
        case balanceRune = "balance_rune"
        case poolUnits = "pool_units"
        case lpUnits = "LP_units"
        case synthUnits = "synth_units"
        case synthSupply = "synth_supply"
        case pendingInboundAsset = "pending_inbound_asset"
        case pendingInboundRune = "pending_inbound_rune"
    }
}

// Structure for LP position from THORNode API
struct ThorchainLPPosition: Codable {
    let asset: String
    let runeAddress: String?
    let assetAddress: String?
    let poolUnits: String
    let runeDepositValue: String
    let assetDepositValue: String
    let runeRedeemValue: String?
    let assetRedeemValue: String?
    let luvi: String?
    let gLPGrowth: String?
    let assetGrowthPct: String?

    enum CodingKeys: String, CodingKey {
        case asset
        case runeAddress = "rune_address"
        case assetAddress = "asset_address"
        case poolUnits = "units"
        case runeDepositValue = "rune_deposit_value"
        case assetDepositValue = "asset_deposit_value"
        case runeRedeemValue = "rune_redeem_value"
        case assetRedeemValue = "asset_redeem_value"
        case luvi
        case gLPGrowth = "glp_growth_pct"
        case assetGrowthPct = "asset_growth_pct"
    }
}

// Structure for LP response from individual pool endpoint
struct ThorchainPoolLPResponse: Codable {
    let asset: String
    let assetAddress: String?
    let lastAddHeight: Int64?
    let units: String
    let pendingRune: String
    let pendingAsset: String
    let runeDepositValue: String
    let assetDepositValue: String

    enum CodingKeys: String, CodingKey {
        case asset
        case assetAddress = "asset_address"
        case lastAddHeight = "last_add_height"
        case units
        case pendingRune = "pending_rune"
        case pendingAsset = "pending_asset"
        case runeDepositValue = "rune_deposit_value"
        case assetDepositValue = "asset_deposit_value"
    }
}

// Structure for Add LP memo data
struct AddLPMemoData {
    let pool: String
    let pairedAddress: String?

    var memo: String {
        if let pairedAddress = pairedAddress {
            return "+:\(pool):\(pairedAddress)"
        } else {
            return "+:\(pool)"
        }
    }
}

// Structure for Remove LP memo data
struct RemoveLPMemoData {
    let pool: String
    let basisPoints: Int // 10000 = 100%

    var memo: String {
        return "-:\(pool):\(basisPoints)"
    }
}
