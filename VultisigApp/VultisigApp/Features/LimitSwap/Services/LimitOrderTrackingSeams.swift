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
    ) throws
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
    ) throws {
        guard let vault = try LimitOrderStorageService.vault(pubKeyECDSA: pubKeyECDSA) else {
            logger.error("No vault for pubKey — cannot record limit-order observation")
            throw LimitOrderObservingError.vaultUnavailable(pubKeyECDSA: pubKeyECDSA)
        }
        try storage.recordObservation(
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

// MARK: - Resolving why an order closed

/// Why an order left the queue.
///
/// The queue tells us THAT an order closed (it disappears) but never WHY:
/// `EventLimitSwapClose` carries the authoritative reason, but it is emitted in
/// EndBlock — exposed by no THORNode REST route and unindexed by Midgard. So the
/// outcome is resolved separately, from the inbound tx's settlement.
enum LimitOrderOutcome: Equatable {
    /// The order executed — an outbound in the target asset settled.
    case filled
    /// The order settled as a REFUND: the funds came back.
    ///
    /// Deliberately not called "expired". A refund is what we can observe; an
    /// expiry is an inference about WHY, and the two aren't the same — a
    /// placement rejected outright (halted pool, bad memo) refunds within
    /// seconds without any TTL elapsing. Telling that user their order "expired"
    /// would be a fabricated explanation of their own funds' history.
    ///
    /// Separating them would need TTL corroboration the tracker doesn't carry:
    /// a closed order is gone from the queue, taking its expiry countdown with
    /// it. So we report the fact and not the story.
    case refunded
    /// Not knowable yet. NOT a state — the caller must keep the order resting
    /// and ask again, never guess.
    case unresolved
}

@MainActor
protocol LimitOrderOutcomeResolving {
    func resolveOutcome(inboundTxHash: String, sourceChain: Chain) async -> LimitOrderOutcome
}

/// Resolves the outcome from Midgard, reading the indexed action's status.
///
/// Midgard indexes a filled limit order as a successful swap and a lapsed one as
/// a refund, which is exactly the "did it fill?" question. (It drops the close
/// REASON entirely — `limit_swap_close` is an explicit no-op in its mux — which
/// is a question we are not asking here.)
///
/// Reads `action.status` directly rather than going through
/// `THORChainTransactionStatusProvider`. That provider folds HTTP 429 and 5xx
/// into `.failed`, which suits a poller that keeps polling — but here `.failed`
/// would mean "refunded", so a rate limit or a bad gateway would irreversibly
/// mark a live resting order expired. The distinction between "the chain says
/// refund" and "Midgard didn't answer" is the entire safety property of this
/// type, and it must not be inferred from an abstraction that discards it.
@MainActor
struct MidgardLimitOutcomeResolver: LimitOrderOutcomeResolving {
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
            guard let action = response.data.actions.first else {
                // Not indexed yet.
                return .unresolved
            }
            switch action.status.lowercased() {
            case "success":
                return .filled
            case "refund":
                return .refunded
            default:
                // "pending", or a status we don't recognise. Either way, not an
                // answer — ask again.
                return .unresolved
            }
        } catch {
            // Rate limits, server errors, timeouts, decode failures. None of
            // these are outcomes; treating any of them as one would close a
            // live order on an infrastructure hiccup.
            logger.debug("Outcome lookup failed for \(inboundTxHash, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .unresolved
        }
    }
}
