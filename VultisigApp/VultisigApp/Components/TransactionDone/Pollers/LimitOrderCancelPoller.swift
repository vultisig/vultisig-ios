//
//  LimitOrderCancelPoller.swift
//  VultisigApp
//
//  `DoneStatusPoller` for the transaction that CANCELS a limit order, and the
//  only place a cancel is credited to the order it names.
//
//  Two things made this its own poller rather than a screen-level side effect:
//
//  1. **A broadcast is not an outcome.** The cancel used to be recorded from
//     `onAppear` on the strength of a non-empty hash. The 2026-07-21 mainnet
//     rehearsal returned a hash, landed in a block, and was refused by
//     THORChain's handler — so the app recorded a cancel that never happened,
//     which permanently disabled the button on an order that was still resting
//     and left its eventual closure ready to be labelled "Cancelled".
//  2. **The generic poller cannot see the refusal.** For a THORChain source the
//     `ChainPoller` reads Midgard actions, and a rejected `MsgDeposit` produces
//     no action at all — so the header would sit on "pending" until it timed
//     out, saying nothing, while the failure was plainly readable in the
//     transaction's own `code` and `raw_log`.
//
//  The order stays `.pending` throughout either way. This never claims the order
//  CLOSED — only the queue can say that, by the order disappearing from it. What
//  a success here buys is the right to interpret that later closure as a
//  cancellation rather than a plain refund.
//

import Foundation
import OSLog

@MainActor
final class LimitOrderCancelPoller: DoneStatusPoller {
    let initialStatus: TransactionStatus

    private let txHash: String
    private let chain: Chain
    private let request: LimitOrderCancelRequest
    private let pubKeyECDSA: String
    private let verifier: LimitOrderCancelVerifying
    private let intents: LimitOrderCancelIntentStoring
    private let config: ChainStatusConfig
    private let logger = Logger(subsystem: "com.vultisig.app", category: "limit-cancel-poller")

    private var pollTask: Task<Void, Never>?

    init(
        txHash: String,
        chain: Chain,
        request: LimitOrderCancelRequest,
        pubKeyECDSA: String,
        // Built in the body rather than defaulted in the signature: a default
        // argument is evaluated in a nonisolated context, and both production
        // collaborators are `@MainActor`.
        verifier: LimitOrderCancelVerifying? = nil,
        intents: LimitOrderCancelIntentStoring? = nil
    ) {
        self.txHash = txHash
        self.chain = chain
        self.request = request
        self.pubKeyECDSA = pubKeyECDSA
        self.verifier = verifier ?? LimitOrderCancelVerifier()
        self.intents = intents ?? LimitOrderCancelIntentStore()
        self.config = ChainStatusConfig.config(for: chain)
        self.initialStatus = .broadcasted(estimatedTime: config.estimatedTime)
    }

    func start(onStatus: @escaping (TransactionStatus) -> Void) {
        guard pollTask == nil else { return }
        let deadline = Date().addingTimeInterval(config.maxWaitTime)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let outcome = await self.verifier.verifyCancelTransaction(txHash: self.txHash, chain: self.chain)
                if Task.isCancelled { return }
                switch outcome {
                case .succeeded, .delivered:
                    // `.delivered` is the weaker of the two and is recorded all
                    // the same: on the L1 route THORChain's verdict is not
                    // observable at all, so a confirmed delivery is the best
                    // evidence that route can ever produce. What stops it
                    // becoming a false "Cancelled" is downstream —
                    // `LimitOrderStorageService.reconcile` credits a cancel only
                    // when the order demonstrably could NOT have expired on its
                    // own, and never relabels a fill.
                    self.recordCancel()
                    onStatus(.confirmed)
                    return
                case let .failed(reason):
                    // Nothing is recorded. The order keeps its live Cancel
                    // button, which is the point: the user has to be able to
                    // try again, and the chain's own words are the only
                    // explanation of why they must.
                    self.logger.error("Cancel \(self.txHash, privacy: .public) failed on-chain")
                    onStatus(.failed(reason: reason))
                    return
                case .unresolved:
                    guard Date() < deadline else {
                        onStatus(.timeout)
                        return
                    }
                }
                do {
                    try await Task.sleep(for: .seconds(self.config.pollInterval))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Attribute the confirmed cancel back to the order it cancels.
    ///
    /// Non-fatal on failure: the transaction already succeeded on-chain, so the
    /// worst case is the order later reading "Refunded" instead of "Cancelled" —
    /// the wrong label on the right outcome. Surfacing an error over a
    /// successful cancel would be the more misleading of the two.
    private func recordCancel() {
        do {
            try intents.recordCancelBroadcast(
                inboundTxHash: request.inboundTxHash,
                pubKeyECDSA: pubKeyECDSA,
                txHash: txHash
            )
        } catch {
            logger.warning("Failed to record confirmed cancel: \(error.localizedDescription, privacy: .public)")
        }
    }
}
