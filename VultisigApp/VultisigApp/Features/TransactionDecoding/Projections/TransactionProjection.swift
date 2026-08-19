//
//  TransactionProjection.swift
//  VultisigApp
//
//  Optional chain-state enrichment for quantities that are settled at execution.
//

import Foundation

/// A chain query key derived only from a counterparty in signed content.
struct ProjectionQueryKey: Hashable {
    let counterparty: DecodedCounterparty

    init?(_ decoded: DecodedTransaction) {
        guard let counterparty = decoded.counterparty else { return nil }
        self.counterparty = counterparty
    }
}

/// Reads chain state using only a signed-content-derived query key.
protocol ProjectionResolving {
    func handles(_ operation: DecodedOperation) -> Bool
    func projection(for decoded: DecodedTransaction, key: ProjectionQueryKey) async -> HeroCoinAmount?
}
