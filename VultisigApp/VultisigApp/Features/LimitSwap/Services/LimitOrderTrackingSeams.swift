//
//  LimitOrderTrackingSeams.swift
//  VultisigApp
//
//  The two collaborators the limit tracker needs beyond HTTP, expressed as
//  protocols so the state machine can be driven in tests without SwiftData or
//  the network.
//

import Foundation
import OSLog
import SwiftData

// MARK: - Writing the authoritative order record

/// Records what the tracker observes onto `LimitOrder`, which is the
/// authoritative record of an order (the tx-history row only mirrors it).
@MainActor
protocol LimitOrderObserving {
    /// - Parameters:
    ///   - inboundTxHash: the order's identity on-chain.
    ///   - pubKeyECDSA: identifies the owning vault.
    ///   - amounts: `nil` means "not observed" and must leave any stored value
    ///     untouched.
    ///   - observedTradeTarget: the queue's own `trade_target`, cross-checked
    ///     against the value recorded at signing before a cancel is built.
    ///   - observedSourceAsset/observedTargetAsset: the assets as THORChain
    ///     itself holds them, i.e. with any abbreviation the placement memo
    ///     carried already resolved. A cancel memo has to spell them in full.
    ///   - timeToExpiryBlocks: the queue's live countdown; `nil` means "not
    ///     observed" and follows the same rule.
    /// - Returns: the status actually recorded, which is not always the one
    ///   observed — a still-resting order with a confirmed cancel against it is
    ///   stored as `.cancelling`. The caller mirrors THIS onto the tx-history
    ///   row so the row and the authoritative order table say the same thing.
    func recordObservation(
        inboundTxHash: String,
        pubKeyECDSA: String,
        status: LimitOrderStatus,
        depositAmount: String?,
        filledInAmount: String?,
        filledOutAmount: String?,
        observedTradeTarget: String?,
        observedSourceAsset: String?,
        observedTargetAsset: String?,
        timeToExpiryBlocks: Int?
    ) throws -> LimitOrderStatus
}

enum LimitOrderObservingError: Error, Equatable {
    case vaultUnavailable(pubKeyECDSA: String)
}

/// Resolves an order's `LimitOrder` row by (inbound hash, vault) and writes
/// through `LimitOrderStorageService`.
@MainActor
struct LimitOrderObserver: LimitOrderObserving {
    private let storage = LimitOrderStorageService()
    private let logger = Logger(subsystem: "com.vultisig.app", category: "limit-order-observer")

    /// Throws — never returns quietly — when the vault can't be resolved.
    ///
    /// The caller releases a terminal order only if this write landed, so
    /// swallowing a lookup failure here would report success for a write that
    /// never happened: the order would be dropped from tracking with
    /// `LimitOrder` left permanently non-terminal and nothing to correct it.
    /// Failing loudly just means the next poll tries again.
    func recordObservation(
        inboundTxHash: String,
        pubKeyECDSA: String,
        status: LimitOrderStatus,
        depositAmount: String?,
        filledInAmount: String?,
        filledOutAmount: String?,
        observedTradeTarget: String?,
        observedSourceAsset: String?,
        observedTargetAsset: String?,
        timeToExpiryBlocks: Int?
    ) throws -> LimitOrderStatus {
        guard let vault = try LimitOrderStorageService.vault(pubKeyECDSA: pubKeyECDSA) else {
            logger.error("No vault for pubKey — cannot record limit-order observation")
            throw LimitOrderObservingError.vaultUnavailable(pubKeyECDSA: pubKeyECDSA)
        }
        return try storage.recordObservation(
            of: "\(inboundTxHash)_\(pubKeyECDSA)",
            status: status,
            depositAmount: depositAmount,
            filledInAmount: filledInAmount,
            filledOutAmount: filledOutAmount,
            observedTradeTarget: observedTradeTarget,
            observedSourceAsset: observedSourceAsset,
            observedTargetAsset: observedTargetAsset,
            timeToExpiryBlocks: timeToExpiryBlocks,
            in: vault
        )
    }
}

// MARK: - The cancel record

/// Reads and writes the cancel transaction recorded against an order.
///
/// Separate from `LimitOrderObserving` because it is written from a different
/// place for a different reason: an observation is what the queue reports, a
/// cancel record is what THIS device did and then verified on-chain.
@MainActor
protocol LimitOrderCancelIntentStoring {
    func pendingCancelBroadcast(inboundTxHash: String, pubKeyECDSA: String) -> String?
    /// Called on a confirmed BROADCAST — a non-empty cancel hash — to move the
    /// order into `.cancelling`. A refusal the chain reports later is undone via
    /// `clearCancelBroadcast`.
    func recordCancelBroadcast(inboundTxHash: String, pubKeyECDSA: String, txHash: String) throws
    /// Called once the cancel transaction is verified `.succeeded` / `.delivered`,
    /// marking it CONFIRMED on-chain. Only a confirmed cancel may be credited a
    /// no-reason refund by `reconcile`; a bare broadcast can show `.cancelling`
    /// but never a terminal `.cancelled`.
    func confirmCancelBroadcast(inboundTxHash: String, pubKeyECDSA: String, txHash: String) throws
    /// Withdraw a record whose transaction failed. Compare-and-set on
    /// `expecting`, so a newer cancel recorded while the old one was being
    /// verified is not withdrawn on the old one's verdict.
    func clearCancelBroadcast(inboundTxHash: String, pubKeyECDSA: String, expecting txHash: String) throws
}

@MainActor
struct LimitOrderCancelIntentStore: LimitOrderCancelIntentStoring {
    private let storage = LimitOrderStorageService()

    func pendingCancelBroadcast(inboundTxHash: String, pubKeyECDSA: String) -> String? {
        guard let vault = try? LimitOrderStorageService.vault(pubKeyECDSA: pubKeyECDSA) else {
            return nil
        }
        return storage.pendingCancelBroadcast(of: orderId(inboundTxHash, pubKeyECDSA), in: vault)
    }

    func recordCancelBroadcast(inboundTxHash: String, pubKeyECDSA: String, txHash: String) throws {
        guard let vault = try LimitOrderStorageService.vault(pubKeyECDSA: pubKeyECDSA) else {
            throw LimitOrderObservingError.vaultUnavailable(pubKeyECDSA: pubKeyECDSA)
        }
        try storage.recordCancelBroadcast(
            of: orderId(inboundTxHash, pubKeyECDSA),
            txHash: txHash,
            in: vault
        )
    }

    func confirmCancelBroadcast(inboundTxHash: String, pubKeyECDSA: String, txHash: String) throws {
        guard let vault = try LimitOrderStorageService.vault(pubKeyECDSA: pubKeyECDSA) else {
            throw LimitOrderObservingError.vaultUnavailable(pubKeyECDSA: pubKeyECDSA)
        }
        try storage.confirmCancelBroadcast(
            of: orderId(inboundTxHash, pubKeyECDSA),
            txHash: txHash,
            in: vault
        )
    }

    func clearCancelBroadcast(inboundTxHash: String, pubKeyECDSA: String, expecting txHash: String) throws {
        guard let vault = try LimitOrderStorageService.vault(pubKeyECDSA: pubKeyECDSA) else {
            throw LimitOrderObservingError.vaultUnavailable(pubKeyECDSA: pubKeyECDSA)
        }
        try storage.clearCancelBroadcast(
            of: orderId(inboundTxHash, pubKeyECDSA),
            expecting: txHash,
            in: vault
        )
    }

    /// The `LimitOrder` primary key, built the same way `persist` builds it.
    private func orderId(_ inboundTxHash: String, _ pubKeyECDSA: String) -> String {
        "\(inboundTxHash)_\(pubKeyECDSA)"
    }
}

// MARK: - Resolving why an order closed

/// Why an order left the queue.
///
/// The queue tells us THAT an order closed (it disappears) but never WHY. The
/// reason comes from Midgard, which indexes the closure as a `refund` action and
/// carries THORChain's own words on it as `metadata.refund.reason` — verbatim
/// `"limit swap cancelled"` or `"limit swap expired"`.
///
/// > This design was originally built on the belief that no such signal existed
/// > — that `EventLimitSwapClose` was EndBlock-only, reachable through no REST
/// > route and unindexed by Midgard, and that a cancellation was therefore
/// > client knowledge or nothing. That was wrong, and a great deal of hedging
/// > downstream of it was hedging against a problem that is not there.
enum LimitOrderOutcome: Equatable {
    /// The order executed — an outbound in the target asset settled.
    case filled
    /// The order settled as a REFUND, with no reason we recognise attached.
    ///
    /// Deliberately not called "expired". A refund is what we observed; an
    /// expiry is a claim about WHY, and the two aren't the same — a placement
    /// rejected outright (halted pool, bad memo) also refunds, within seconds,
    /// with no TTL elapsed. This is the fail-closed answer for a reason string
    /// that is missing or that THORChain has since reworded: today's behaviour,
    /// which a future protocol change degrades INTO rather than through.
    case refunded
    /// THORChain closed the order because a cancel matched it — its own words,
    /// `"limit swap cancelled"`.
    ///
    /// Independent of whether THIS device sent that cancel, which is the point:
    /// an order cancelled from another device, or from a different wallet
    /// entirely, is labelled correctly here and could not be before.
    case cancelled
    /// THORChain closed the order because its TTL elapsed — its own words,
    /// `"limit swap expired"`.
    case expired
    /// Not knowable yet. NOT a state — the caller must keep the order resting
    /// and ask again, never guess.
    case unresolved
}

/// Midgard's `metadata.refund.reason` for a limit order THORChain closed because
/// a cancel matched it.
///
/// Matched EXACTLY. Anything else — a reworded string, a reason for some other
/// kind of refund, nothing at all — falls to `.refunded`, which is what this
/// tracker reported before the reason was available at all. A protocol change
/// therefore costs a label, never a wrong one.
private let limitSwapCancelledReason = "limit swap cancelled"
private let limitSwapExpiredReason = "limit swap expired"

/// Read THORChain's own account of why an order closed.
///
/// Pure, and separate from the HTTP that fetches it, because this mapping is the
/// whole of the decision: everything else in the resolver is about telling an
/// answer from a failure to get one.
func limitOrderCloseOutcome(refundReason: String?) -> LimitOrderOutcome {
    let normalized = refundReason?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    switch normalized {
    case limitSwapCancelledReason:
        return .cancelled
    case limitSwapExpiredReason:
        return .expired
    default:
        // The funds came back and we cannot say why. `.refunded` is exactly
        // that statement.
        return .refunded
    }
}

@MainActor
protocol LimitOrderOutcomeResolving {
    func resolveOutcome(inboundTxHash: String, sourceChain: Chain) async -> LimitOrderOutcome
}

/// Resolves the outcome from Midgard, keyed on the action's TYPE and, for a
/// closure, on THORChain's own reason for it.
///
/// Midgard indexes an order's whole life against its placement hash: a
/// `limit_swap` action when it is placed, a `swap` when it executes, and a
/// `refund` when it closes unfilled — the last of which carries
/// `metadata.refund.reason`, verbatim `"limit swap cancelled"` or
/// `"limit swap expired"`.
///
/// ⚠️ **`type`, never `status`.** Midgard's `status` is only ever `success` or
/// `pending` and describes whether the OUTBOUND settled, not what happened to
/// the order. This read `status` and compared it against `"refund"` — a value
/// that field never takes — so a closed order matched `"success"` and resolved
/// as FILLED, whether it had filled, expired or been cancelled. A resting
/// order's placement action alone would have done the same.
///
/// A `refund` outranks a `swap` when both are present: that is a partial fill
/// followed by a closure, and what closed the order is the refund. The fill
/// split is reported separately, from the queue's own last observation.
///
/// Reads the actions directly rather than going through
/// `THORChainTransactionStatusProvider`. That provider folds HTTP 429 and 5xx
/// into `.failed`, which suits a poller that keeps polling — but here `.failed`
/// would mean "closed", so a rate limit or a bad gateway would irreversibly
/// close a live resting order. The distinction between "the chain says refund"
/// and "Midgard didn't answer" is the entire safety property of this type, and
/// it must not be inferred from an abstraction that discards it.
@MainActor
struct MidgardLimitOutcomeResolver: LimitOrderOutcomeResolving {
    /// Midgard action types. `limitSwap` is the PLACEMENT and is deliberately
    /// not an outcome — an order that is still resting has exactly this and
    /// nothing else.
    private enum ActionType {
        static let refund = "refund"
        static let swap = "swap"
    }

    /// The only two values Midgard's `status` takes. It says whether the
    /// OUTBOUND settled — not what happened to the order.
    private enum ActionStatus {
        static let success = "success"
    }

    private let httpClient: HTTPClientProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "limit-outcome-resolver")

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func resolveOutcome(inboundTxHash: String, sourceChain: Chain) async -> LimitOrderOutcome {
        do {
            let response = try await httpClient.request(
                THORChainTransactionStatusAPI.getActions(txHash: inboundTxHash, chain: sourceChain),
                responseType: THORChainActionsResponse.self
            )
            let actions = response.data.actions
            if let refund = actions.first(where: { $0.type.lowercased() == ActionType.refund }) {
                // ⚠️ Indexed is not settled. `.refunded` / `.cancelled` /
                // `.expired` all say the funds came back, and a `pending`
                // refund is one whose outbound has not been sent yet — so wait
                // a poll rather than say it early.
                //
                // And do NOT fall through to the fill below while waiting. An
                // order that partially filled and THEN closed has both actions
                // indexed; reading the older one because the newer one is still
                // pending would report it FILLED, terminally, on the strength
                // of a fill that was only part of the story.
                guard refund.status.lowercased() == ActionStatus.success else {
                    return .unresolved
                }
                let reason = refund.metadata?.refund?.reason
                let outcome = limitOrderCloseOutcome(refundReason: reason)
                if outcome == .refunded {
                    // Worth noticing: either THORChain reworded a reason we key
                    // on, or this refund is one we have never seen. Both mean
                    // the label degrades to `.refunded`, which is safe, and both
                    // are things we would rather find out about than not.
                    logger.info("Limit order \(inboundTxHash, privacy: .public) refunded with an unrecognised reason: \(reason ?? "<none>", privacy: .public)")
                }
                return outcome
            }
            if actions.contains(where: {
                $0.type.lowercased() == ActionType.swap && $0.status.lowercased() == ActionStatus.success
            }) {
                return .filled
            }
            // Only the placement action, an outbound still in flight, or nothing
            // at all — either way, not an answer yet.
            return .unresolved
        } catch {
            // Rate limits, server errors, timeouts, decode failures. None of
            // these are outcomes; treating any of them as one would close a
            // live order on an infrastructure hiccup.
            logger.debug("Outcome lookup failed for \(inboundTxHash, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .unresolved
        }
    }
}
