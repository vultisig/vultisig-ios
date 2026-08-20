//
//  TransactionProjection.swift
//  VultisigApp
//
//  An execution-set quantity pairs an optional estimate with the signed scope
//  that remains true when no estimate arrives.
//

import Foundation

struct TransactionProjection: Hashable {

    /// What the operation is expected to settle at, when available.
    let estimate: HeroCoinAmount?

    /// What the transaction commits to, in words. Always present.
    let scope: String
}

/// A chain query key derived only from a counterparty in signed content. There is
/// deliberately no initializer accepting a peer-supplied bare address.
struct ProjectionQueryKey: Hashable {

    let counterparty: DecodedCounterparty

    /// Missing signed counterparties degrade to scope-only presentation.
    init?(_ decoded: DecodedTransaction) {
        guard let counterparty = decoded.counterparty else { return nil }
        self.counterparty = counterparty
    }
}

/// Reads chain state using only a signed-content-derived query key.
protocol ProjectionResolving {
    /// Whether this resolver answers for the operation at all.
    func handles(_ operation: DecodedOperation) -> Bool

    /// The projected quantity, or `nil` to retain scope-only presentation.
    func projection(for decoded: DecodedTransaction, key: ProjectionQueryKey) async -> HeroCoinAmount?
}
