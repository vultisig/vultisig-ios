//
//  THORChainLiquidityProviderResponse.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/10/2025.
//

import Foundation

/// Response from /thorchain/pool/{asset-id}/liquidity_provider/{wallet-address}
struct THORChainLiquidityProviderResponse: Codable {
    let asset: String
    let runeAddress: String
    let assetAddress: String
    let lastAddHeight: Int64
    let units: String
    let pendingRune: String
    let pendingAsset: String
    let pendingTxId: String?
    let runeDepositValue: String
    let assetDepositValue: String
    let runeRedeemValue: String
    let assetRedeemValue: String
    let luviDepositValue: String
    let luviRedeemValue: String
    let luviGrowthPct: String

    enum CodingKeys: String, CodingKey {
        case asset
        case runeAddress = "rune_address"
        case assetAddress = "asset_address"
        case lastAddHeight = "last_add_height"
        case units
        case pendingRune = "pending_rune"
        case pendingAsset = "pending_asset"
        case pendingTxId = "pending_tx_id"
        case runeDepositValue = "rune_deposit_value"
        case assetDepositValue = "asset_deposit_value"
        case runeRedeemValue = "rune_redeem_value"
        case assetRedeemValue = "asset_redeem_value"
        case luviDepositValue = "luvi_deposit_value"
        case luviRedeemValue = "luvi_redeem_value"
        case luviGrowthPct = "luvi_growth_pct"
    }

    /// Current RUNE amount (redeemable value)
    var runeRedeemValueBigInt: UInt64 {
        UInt64(runeRedeemValue) ?? 0
    }

    /// Current asset amount (redeemable value)
    var assetRedeemValueBigInt: UInt64 {
        UInt64(assetRedeemValue) ?? 0
    }

    /// Liquidity units
    var unitsBigInt: UInt64 {
        UInt64(units) ?? 0
    }

    /// LUVI growth as percentage
    var luviGrowthPercentage: Double {
        Double(luviGrowthPct) ?? 0.0
    }
}
