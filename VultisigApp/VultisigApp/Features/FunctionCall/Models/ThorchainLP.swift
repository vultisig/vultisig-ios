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
