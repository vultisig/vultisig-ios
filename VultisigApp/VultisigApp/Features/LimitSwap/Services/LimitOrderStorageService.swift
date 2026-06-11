//
//  LimitOrderStorageService.swift
//  VultisigApp
//

import Foundation
import SwiftData

extension Notification.Name {
    /// Posted on the main actor after `LimitOrderStorageService.persist` /
    /// `updateStatus` saves changes to SwiftData. Phase 2's Open-Orders surface
    /// in TX History should observe this to refresh — `@ObservedObject` does
    /// not propagate in-place mutations of nested `@Model` arrays back to the
    /// parent vault.
    static let limitOrdersDidChange = Notification.Name("com.vultisig.app.limitOrdersDidChange")
}

enum LimitOrderStorageError: Error, Equatable {
    case duplicate(id: String)
    case notFound(id: String)
    /// A record was handed to `persist` before its inbound TX hash was spliced
    /// in. The unique id is `inboundTxHash + pubKeyECDSA`; persisting with an
    /// empty hash would make every pre-broadcast order collide on `"_pubkey"`,
    /// silently dropping all but the first. Fail loud instead of corrupting the
    /// open-orders table.
    case emptyInboundTxHash
}

struct LimitOrderStorageService {

    /// Persists a freshly-placed limit order. Idempotency is the caller's
    /// responsibility — the inbound TX hash is what makes each order unique,
    /// and the keysign flow only invokes this on broadcast success.
    @discardableResult
    @MainActor
    func persist(_ record: LimitOrderRecord, for vault: Vault) throws -> LimitOrder {
        guard !record.inboundTxHash.isEmpty else {
            throw LimitOrderStorageError.emptyInboundTxHash
        }
        let id = makeId(inboundTxHash: record.inboundTxHash, vault: vault)
        if vault.limitOrders.contains(where: { $0.id == id }) {
            throw LimitOrderStorageError.duplicate(id: id)
        }
        let model = LimitOrder(
            id: id,
            inboundTxHash: record.inboundTxHash,
            sourceAsset: record.sourceAsset,
            sourceAmount: record.sourceAmount,
            sourceDecimals: record.sourceDecimals,
            targetAsset: record.targetAsset,
            destAddress: record.destAddress,
            targetPrice: record.targetPrice,
            expiryBlocks: record.expiryBlocks,
            createdAt: record.createdAt,
            status: record.status,
            vault: vault
        )
        Storage.shared.modelContext.insert(model)
        try saveAndNotify()
        return model
    }

    /// Returns this vault's orders sorted newest-first.
    @MainActor
    func fetchAll(for vault: Vault) -> [LimitOrder] {
        vault.limitOrders.sorted(by: { $0.createdAt > $1.createdAt })
    }

    /// In-place status update. Throws if the given id isn't on this vault.
    @MainActor
    func updateStatus(of orderId: String, to status: LimitOrderStatus, in vault: Vault) throws {
        guard let order = vault.limitOrders.first(where: { $0.id == orderId }) else {
            throw LimitOrderStorageError.notFound(id: orderId)
        }
        order.statusRawValue = status.rawValue
        try saveAndNotify()
    }

    @MainActor
    private func makeId(inboundTxHash: String, vault: Vault) -> String {
        "\(inboundTxHash)_\(vault.pubKeyECDSA)"
    }
}

private extension LimitOrderStorageService {
    @MainActor
    func saveAndNotify() throws {
        try Storage.shared.save()
        NotificationCenter.default.post(name: .limitOrdersDidChange, object: nil)
    }
}
