//
//  MayaLiquidityProvider.swift
//  VultisigApp
//

import Foundation

/// A vault's record on one MayaChain pool, from
/// `/mayachain/pool/{pool}/liquidity_provider/{address}`.
///
/// `pending_cacao` is in CACAO's own 1e10 base units; `pending_asset` is in
/// MayaChain's 1e8 fixed point whatever the asset's decimals.
struct MayaLiquidityProvider: Decodable, Equatable {
    let asset: String
    let cacaoAddress: String?
    let assetAddress: String?
    let units: String
    let pendingCacao: String
    let pendingAsset: String
    /// Inbound hash of the side that arrived first; set only while the add is
    /// half-open.
    let pendingTxId: String?
    /// The refund happens at `lastAddHeight + PendingLiquidityAgeLimit`.
    let lastAddHeight: Int64?

    enum CodingKeys: String, CodingKey {
        case asset
        case cacaoAddress = "cacao_address"
        case assetAddress = "asset_address"
        case units
        case pendingCacao = "pending_cacao"
        case pendingAsset = "pending_asset"
        case pendingTxId = "pending_tx_id"
        case lastAddHeight = "last_add_height"
    }

    init(
        asset: String,
        cacaoAddress: String?,
        assetAddress: String?,
        units: String,
        pendingCacao: String,
        pendingAsset: String,
        pendingTxId: String?,
        lastAddHeight: Int64?
    ) {
        self.asset = asset
        self.cacaoAddress = cacaoAddress
        self.assetAddress = assetAddress
        self.units = units
        self.pendingCacao = pendingCacao
        self.pendingAsset = pendingAsset
        self.pendingTxId = pendingTxId
        self.lastAddHeight = lastAddHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        asset = try container.decode(String.self, forKey: .asset)
        cacaoAddress = try container.decodeIfPresent(String.self, forKey: .cacaoAddress)
        assetAddress = try container.decodeIfPresent(String.self, forKey: .assetAddress)
        units = try container.decodeIfPresent(String.self, forKey: .units) ?? "0"
        pendingCacao = try container.decodeIfPresent(String.self, forKey: .pendingCacao) ?? "0"
        pendingAsset = try container.decodeIfPresent(String.self, forKey: .pendingAsset) ?? "0"
        pendingTxId = try container.decodeIfPresent(String.self, forKey: .pendingTxId)
        lastAddHeight = try container.decodeIfPresent(Int64.self, forKey: .lastAddHeight)
    }
}

/// Whether MayaChain will accept a paired add naming a given CACAO and asset
/// address against a vault's record.
enum MayaLPPairing: Equatable {
    /// A paired add is credited, or held pending, against this record.
    case pairable
    /// The vault holds a live CACAO-only position: mayanode records no asset
    /// address on it, so any add naming one is refunded.
    case singleSidedPosition
    /// The record is keyed to addresses other than the ones the add names.
    case addressMismatch
}

extension MayaLiquidityProvider {
    /// Mirrors mayanode's `addLiquidity` address rules. A zero-unit record with
    /// nothing pending takes whatever the add names; a pending half has already
    /// fixed both addresses; a live position keeps the asset address it was
    /// created with, or none if it was created CACAO-only.
    func pairing(cacaoAddress cacao: String, assetAddress assetAddr: String) -> MayaLPPairing {
        let hasUnits = (Decimal(string: units) ?? 0) > 0
        let recordedCacao = cacaoAddress ?? ""
        let recordedAsset = assetAddress ?? ""

        guard hasUnits else {
            guard pendingTxId?.nilIfEmpty != nil else { return .pairable }
            let matches = recordedCacao.caseInsensitiveCompare(cacao) == .orderedSame
                && recordedAsset.caseInsensitiveCompare(assetAddr) == .orderedSame
            return matches ? .pairable : .addressMismatch
        }

        if recordedAsset.isEmpty { return .singleSidedPosition }
        return recordedAsset.caseInsensitiveCompare(assetAddr) == .orderedSame ? .pairable : .addressMismatch
    }
}
