//
//  MayaPendingLPDeposit.swift
//  VultisigApp
//

import Foundation

/// One half of a paired MayaChain add that MayaChain is still holding.
///
/// A paired add mints no LP units until both sides arrive, so the record reads
/// as an empty position until then. If the matching side never arrives,
/// MayaChain refunds the deposit at `lastAddHeight + PendingLiquidityAgeLimit`.
struct MayaPendingLPDeposit: Equatable, Identifiable {
    let pool: String
    /// In CACAO's own 1e10 base units.
    let pendingCacao: Decimal
    /// In MayaChain's 1e8 fixed point, whatever the asset's decimals.
    let pendingAsset: Decimal
    /// Inbound hash of the side that already arrived.
    let pendingTxId: String?
    /// The address MayaChain expects the missing side to come from: the asset
    /// address when CACAO is pending, the CACAO address when the asset is.
    let pairedAddress: String?
    /// Blocks left before the pending side is refunded, clamped at zero, or nil
    /// when unknown.
    var blocksUntilRefund: Int64?

    var id: String { pool }

    /// True while MayaChain holds the CACAO half, so the asset half is missing.
    var isCacaoPending: Bool { pendingCacao > 0 }

    init(
        pool: String,
        pendingCacao: Decimal,
        pendingAsset: Decimal,
        pendingTxId: String?,
        pairedAddress: String?,
        blocksUntilRefund: Int64?
    ) {
        self.pool = pool
        self.pendingCacao = pendingCacao
        self.pendingAsset = pendingAsset
        self.pendingTxId = pendingTxId
        self.pairedAddress = pairedAddress
        self.blocksUntilRefund = blocksUntilRefund
    }

    /// Reads a record as a half-finished paired add, or nil when nothing is
    /// pending on it. Nonzero `units` does not rule it out: a top-up's pending
    /// half sits on a live position's record.
    init?(pool: String, record: MayaLiquidityProvider) {
        let cacao = Decimal(string: record.pendingCacao) ?? 0
        let asset = Decimal(string: record.pendingAsset) ?? 0
        guard cacao > 0 || asset > 0 else { return nil }

        self.init(
            pool: pool,
            pendingCacao: cacao,
            pendingAsset: asset,
            pendingTxId: record.pendingTxId?.nilIfEmpty,
            pairedAddress: (cacao > 0 ? record.assetAddress : record.cacaoAddress)?.nilIfEmpty,
            blocksUntilRefund: nil
        )
    }

    static func blocksUntilRefund(lastAddHeight: Int64?, ageLimit: Int64?, currentHeight: Int64?) -> Int64? {
        guard let lastAddHeight, let ageLimit, let currentHeight else { return nil }
        return max(0, lastAddHeight + ageLimit - currentHeight)
    }
}
