//
//  LimitOrderCancelL1Destination.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Where an L1-originated cancel is sent, and what it must carry.
///
/// Resolved live before the confirmation screen renders — both values come from
/// the same `inbound_addresses` row and neither can be defaulted:
///
/// - the vault address rotates, and a stale one sends funds nowhere recoverable;
/// - the dust must clear THORChain's `dust_threshold`, below which Bifrost
///   ignores the transaction entirely.
struct LimitOrderCancelL1Destination: Hashable, Sendable {
    let inboundAddress: String
    /// Dust in the source coin's smallest units.
    let dust: BigInt
    /// The same amount in the coin's natural units, as the string the
    /// transaction builder hands to the send pipeline.
    let dustDecimalString: String
    /// Formatted for display, e.g. "2 DOGE" — shown BEFORE signing because this
    /// amount is `donateToPool`'d with no refund path.
    let dustDisplay: String
}
