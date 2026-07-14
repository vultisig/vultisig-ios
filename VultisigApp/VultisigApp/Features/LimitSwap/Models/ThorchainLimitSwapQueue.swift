//
//  ThorchainLimitSwapQueue.swift
//  VultisigApp
//
//  Wire models for THORNode's advanced-swap-queue routes, verified live on
//  mainnet through our own gateway.
//
//  Two shapes worth knowing before reading:
//
//  - `/thorchain/queue/limit_swaps` returns an OBJECT (`{"limit_swaps":[…]}`),
//    not a bare array.
//  - Every numeric field arrives as a STRING, including the fill amounts. They
//    are 1e8 fixed-point integers that overflow nothing here only because we
//    keep them as strings and let the caller widen them deliberately.
//

import Foundation

// MARK: - queue/limit_swaps

struct ThorchainLimitSwapQueueResponse: Decodable, Equatable {
    /// `nil` when the `limit_swaps` key was ABSENT — which is not the same as
    /// an empty queue, and must never be flattened into one.
    ///
    /// An order's DISAPPEARANCE from this list is what marks it terminal. So
    /// "the queue is empty" is a load-bearing claim: if an unrecognised 200
    /// envelope (or a future response shape) silently decoded as "no resting
    /// orders", every tracked order would be closed at once on the strength of
    /// a response we didn't actually understand.
    ///
    /// We have observed the populated shape live; we have NOT confirmed what an
    /// empty result looks like, so the ambiguity is modelled rather than
    /// guessed. Callers must treat `nil` as "no information" and leave orders
    /// resting; only an explicit `[]` means the sender has none.
    let limitSwaps: [ThorchainLimitSwapQueueEntry]?

    enum CodingKeys: String, CodingKey {
        case limitSwaps = "limit_swaps"
    }
}

struct ThorchainLimitSwapQueueEntry: Decodable, Equatable {
    /// Blocks remaining before the order expires. THORChain blocks are ~6s.
    let timeToExpiryBlocks: String?
    /// Blocks elapsed since the order was placed. Preferred over
    /// `created_timestamp`, which THORNode hardcodes to `0` (verbatim: "We
    /// don't have timestamp info readily available").
    let blocksSinceCreated: String?
    let swap: ThorchainQueuedSwap

    enum CodingKeys: String, CodingKey {
        case timeToExpiryBlocks = "time_to_expiry_blocks"
        case blocksSinceCreated = "blocks_since_created"
        case swap
    }
}

struct ThorchainQueuedSwap: Decodable, Equatable {
    let tx: ThorchainQueuedSwapTx
    let state: ThorchainQueuedSwapState?

    enum CodingKeys: String, CodingKey {
        case tx
        case state
    }
}

struct ThorchainQueuedSwapTx: Decodable, Equatable {
    /// The original inbound tx hash — the identity we match orders on, and what
    /// `LimitOrder.inboundTxHash` already stores.
    let id: String
    let fromAddress: String?
    let memo: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fromAddress = "from_address"
        case memo
    }
}

/// The order's fill accounting, in 1e8 fixed-point source/target units.
///
/// `deposit` is what went in; `in` is how much of it has been swapped so far;
/// `out` is what has been paid out. An order fills via streaming sub-swaps, so
/// `0 < in < deposit` is a real, stable state — usually transient, but
/// long-lived when the price crosses and then retreats.
struct ThorchainQueuedSwapState: Decodable, Equatable {
    let deposit: String?
    let inAmount: String?
    let outAmount: String?
    /// Present on orders that TRIED to execute and missed. This does NOT mean
    /// the order failed — it is still resting. Surfacing these as errors would
    /// be actively wrong.
    let failedSwapReasons: [String]?

    enum CodingKeys: String, CodingKey {
        case deposit
        // `in` / `out` are Swift keywords; the wire names are unavoidable.
        case inAmount = "in"
        case outAmount = "out"
        case failedSwapReasons = "failed_swap_reasons"
    }
}

// MARK: - queue/swap/details error body

/// The body THORNode returns with **400** once an order is no longer queued.
/// A 400 here is a state ("closed"), not a transport error.
struct ThorchainQueueErrorResponse: Decodable, Equatable {
    let code: Int?
    let message: String?
}

extension ThorchainQueueErrorResponse {
    /// Marker in THORNode's not-queued message. Matched as a SUBSTRING: the
    /// message embeds the tx id and a trailing `: invalid request`, so neither
    /// equality nor a prefix match would hold.
    private static let notFoundMarker = "not found in any queue"
    /// The code THORNode returns with the not-queued message.
    private static let notQueuedCode = 3
    /// The label the tx id follows in the message.
    private static let txIdLabel = "tx_id"

    /// True when this 400 means "**this** order is no longer in the queue" —
    /// i.e. it went terminal — rather than a genuinely malformed request.
    ///
    /// Deliberately strict on all three counts, because this is the ONLY signal
    /// that closes an order and closing one wrongly tells the user their funds
    /// resolved when they are still resting:
    /// - the code must be the not-queued code;
    /// - the message must carry the not-queued marker;
    /// - the message must name the hash we ASKED about, so a response about a
    ///   different order can never close this one.
    ///
    /// Every mismatch fails to `false`, which leaves the order resting and
    /// retried. That is the safe direction: a wrongly-open order is corrected by
    /// the next poll, a wrongly-closed one is never revisited.
    ///
    /// The hash compares case-insensitively (hex case carries no meaning); the
    /// marker does not — a reworded message should read as "unknown", not
    /// "closed".
    func indicatesOrderClosed(forTxHash txHash: String) -> Bool {
        guard code == Self.notQueuedCode, let message, !txHash.isEmpty else { return false }
        guard message.contains(Self.notFoundMarker) else { return false }
        guard let named = Self.txId(in: message) else { return false }
        return named.compare(txHash, options: .caseInsensitive) == .orderedSame
    }

    /// The complete tx id named in the message, or `nil` if it isn't shaped as
    /// expected.
    ///
    /// Compared as a whole token rather than searched for as a substring: a
    /// substring test would let a short or truncated hash match a longer one
    /// (`ABC` inside `ABC123`) and close the wrong order.
    private static func txId(in message: String) -> String? {
        guard let labelRange = message.range(of: txIdLabel) else { return nil }
        return message[labelRange.upperBound...]
            .split(separator: " ", omittingEmptySubsequences: true)
            .first
            .map(String.init)
    }
}
