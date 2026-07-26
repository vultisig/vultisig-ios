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
    /// The order's TARGET asset as THORChain itself holds it — i.e. AFTER
    /// `fuzzyAssetMatch` expanded whatever abbreviation the placement memo
    /// carried.
    ///
    /// This is the only place the full identifier can be read back. A placement
    /// memo may say `ETH.USDC-06EB48`; the order is indexed under
    /// `ETH.USDC-0XA0B8…`, and a cancel — the one inbound memo type that skips
    /// fuzzy matching — has to spell it the long way or it keys an empty bucket.
    let targetAsset: ThorchainWireAsset?
    /// The order's trade target (the LIM its placement memo encoded), in the
    /// target asset's 1e8 fixed point. This is `MsgSwap.TradeTarget` verbatim.
    ///
    /// Read for one reason: it is half of the pair THORChain addresses a resting
    /// order by, so it cross-checks the value we recorded at signing before a
    /// cancel is built from it. (`state.deposit` is the other half — THORNode
    /// assigns it from `Tx.Coins[0].Amount`.) A mismatch disables cancelling
    /// rather than signing a memo that would match nothing.
    let tradeTarget: String?

    enum CodingKeys: String, CodingKey {
        case tx
        case state
        case tradeTarget = "trade_target"
        case targetAsset = "target_asset"
    }
}

struct ThorchainQueuedSwapTx: Decodable, Equatable {
    /// The original inbound tx hash — the identity we match orders on, and what
    /// `LimitOrder.inboundTxHash` already stores.
    let id: String
    let fromAddress: String?
    let memo: String?
    /// What was actually deposited, as THORChain resolved it. `coins[0]` is the
    /// swap's source coin — `state.deposit` is this entry's amount, assigned
    /// verbatim — so `coins[0].asset` is the SOURCE half of the pair a cancel
    /// memo has to name in full.
    let coins: [ThorchainQueuedCoin]?

    enum CodingKeys: String, CodingKey {
        case id
        case fromAddress = "from_address"
        case memo
        case coins
    }
}

struct ThorchainQueuedCoin: Decodable, Equatable {
    let asset: ThorchainWireAsset?
    let amount: String?
}

/// A `common.Asset` off the wire, reduced to the string a memo spells it with.
///
/// Decodes BOTH shapes deliberately. THORNode's queriers render assets through
/// `Asset.MarshalJSON`, i.e. as the flat string `ETH.USDC-0XA0B8…`; but the same
/// message marshalled by protobuf-JSON comes out as an object of its
/// chain/symbol/flags fields. Which one a given route uses is a property of that
/// route's marshaller, not of the type, and this decoder is the only reader of
/// an asset whose exact spelling we then SIGN. Accepting both costs a dozen
/// lines; guessing wrong costs a cancel that silently matches nothing.
struct ThorchainWireAsset: Decodable, Equatable {
    /// The asset as a memo spells it — `THOR.RUNE`, `ETH.USDC-0XA0B8…`,
    /// `ETH-USDC-0XA0B8…` (secured), `ETH/USDC-0XA0B8…` (synth).
    let memoForm: String

    private enum CodingKeys: String, CodingKey {
        case chain
        case symbol
        case synth
        case trade
        case secured
    }

    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            memoForm = text
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let chain = try container.decode(String.self, forKey: .chain)
        let symbol = try container.decode(String.self, forKey: .symbol)
        // Mirrors `common.Asset.String()`: one separator per flavour, and the
        // layer-1 `.` when none of the flags is set.
        let separator: String
        if try container.decodeIfPresent(Bool.self, forKey: .synth) == true {
            separator = "/"
        } else if try container.decodeIfPresent(Bool.self, forKey: .trade) == true {
            separator = "~"
        } else if try container.decodeIfPresent(Bool.self, forKey: .secured) == true {
            separator = "-"
        } else {
            separator = "."
        }
        memoForm = "\(chain)\(separator)\(symbol)"
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
