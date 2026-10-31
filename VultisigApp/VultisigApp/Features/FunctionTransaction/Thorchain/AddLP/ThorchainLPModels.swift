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

    var isAvailable: Bool {
        status.caseInsensitiveCompare("Available") == .orderedSame
    }

    var isStaged: Bool {
        status.caseInsensitiveCompare("Staged") == .orderedSame
    }

    /// Pools that may receive a paired LP add. Suspended or unknown statuses are hidden.
    var supportsPairedLPAdd: Bool {
        isAvailable || isStaged
    }

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

/// A MayaChain pool as `/mayachain/pools` lists it. Maya names the protocol
/// side `balance_cacao`, so the THORChain model cannot decode it directly; the
/// LP flows only read the asset and status, and the rest maps across.
struct MayaChainPool: Decodable {
    let asset: String
    let status: String
    let balanceCacao: String
    let balanceAsset: String
    let poolUnits: String
    let lpUnits: String
    let synthUnits: String
    let synthSupply: String
    let pendingInboundCacao: String
    let pendingInboundAsset: String

    enum CodingKeys: String, CodingKey {
        case asset
        case status
        case balanceCacao = "balance_cacao"
        case balanceAsset = "balance_asset"
        case poolUnits = "pool_units"
        case lpUnits = "LP_units"
        case synthUnits = "synth_units"
        case synthSupply = "synth_supply"
        case pendingInboundCacao = "pending_inbound_cacao"
        case pendingInboundAsset = "pending_inbound_asset"
    }

    /// The shared pool model, with CACAO in the protocol-side fields.
    var pool: ThorchainPool {
        ThorchainPool(
            asset: asset,
            status: status,
            balanceAsset: balanceAsset,
            balanceRune: balanceCacao,
            poolUnits: poolUnits,
            lpUnits: lpUnits,
            synthUnits: synthUnits,
            synthSupply: synthSupply,
            pendingInboundAsset: pendingInboundAsset,
            pendingInboundRune: pendingInboundCacao
        )
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
