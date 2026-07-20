//
//  LimitOrderCancelRequest.swift
//  VultisigApp
//

import Foundation

/// Everything the cancel confirmation screen and its transaction builder need,
/// resolved BEFORE navigation.
///
/// The memo is carried rather than rebuilt downstream: it is derived from the
/// exact integers recorded at signing, and `limitOrderCancelEligibility` has
/// already decided this order may be cancelled at all. Rebuilding it on the
/// other side of a navigation boundary would let the check and the signed bytes
/// drift apart — and a cancel memo that addresses the wrong bucket fails
/// silently.
///
/// `Hashable` so it can ride inside `FunctionTransactionType` through a
/// navigation `Route`.
struct LimitOrderCancelRequest: Hashable, Sendable {
    /// Identifies the `LimitOrder` row to mark cancelled once the cancel is
    /// broadcast.
    let orderId: String
    /// The order's on-chain identity, shown for reference.
    let inboundTxHash: String
    /// The `m=<` memo, already built and validated.
    let memo: String
    let sourceAsset: String
    let targetAsset: String
    /// Other RESTING orders that share this one's THORChain bucket.
    ///
    /// Non-zero means the cancel may close a different order than the one the
    /// user tapped: THORChain addresses orders by (assets, ratio) + sender and
    /// takes the FIRST match, never by tx hash. The confirmation warns rather
    /// than blocks — blocking would strand the user with no way out.
    let duplicateRestingOrderCount: Int
}
