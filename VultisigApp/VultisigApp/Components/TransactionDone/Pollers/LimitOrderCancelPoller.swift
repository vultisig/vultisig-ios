//
//  LimitOrderCancelPoller.swift
//  VultisigApp
//
//  `DoneStatusPoller` for the transaction that CANCELS a limit order. It moves
//  the order into `.cancelling` the instant the cancel keysign broadcasts, then
//  watches that transaction so it can undo the move if the chain refuses it.
//
//  **Entry into `.cancelling` is on broadcast, not on confirmation.** A confirmed
//  broadcast — a non-empty hash, the same signal `SendDoneScreen`/`SwapDoneScreen`
//  use to know a tx went out — is what enters `.cancelling`. Gating it on the
//  chain's answer instead left `.cancelling` unobservable for a fast cancel:
//  worst on the L1 route, where the dust tx does not mine for ~12s and THORChain
//  has usually pulled the order from the queue by then, so the tracker resolves
//  `.pending → .cancelled` straight from the chain's reason and the in-flight
//  state is never seen. Broadcast time is block-independent, and it runs before
//  the user can tap Done and tear this poller down.
//
//  Safe only because the cancel hash no longer labels the CLOSURE. `.cancelling`
//  is a statement about OUR transaction, never the order's fate; the terminal
//  `.cancelled`/`.expired`/`.refunded` label comes from THORChain's own reason
//  (via Midgard), so an optimistic hash can show the in-flight state but can
//  never manufacture a false terminal "Cancelled".
//
//  The failure half stays. A `MsgDeposit` the handler refuses produces no Midgard
//  action, so the generic `ChainPoller` would sit on "pending" forever — only
//  this poller reads the transaction's own `code`/`raw_log`. On a refusal it
//  WITHDRAWS the record, dropping the order back to `.pending` with its Cancel
//  button live again. The same self-heal runs independently in the tracker
//  (`verifyPendingCancel`) for an app that left this screen before the chain
//  answered.
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
        // Enter `.cancelling` NOW, on this confirmed broadcast — synchronously,
        // before the poll task or any user tap. This is the only entry into
        // `.cancelling`; see the file header for why it must not wait for the
        // chain's answer.
        recordCancelBroadcast()
        let deadline = Date().addingTimeInterval(config.maxWaitTime)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let outcome = await self.verifier.verifyCancelTransaction(txHash: self.txHash, chain: self.chain)
                if Task.isCancelled { return }
                switch outcome {
                case .succeeded, .delivered:
                    // Already recorded `.cancelling` on broadcast; now the chain
                    // has confirmed the transaction. Mark it confirmed — that is
                    // what unlocks `reconcile`'s terminal fallback, so a genuine
                    // cancel whose closure the chain reports with no reason we
                    // recognise can still be credited. `.delivered` (the L1
                    // route's strongest answer, since THORChain's verdict on it is
                    // not observable) counts as confirmation here; the guard
                    // against over-claiming is downstream, in `reconcile`'s TTL
                    // rule, which never relabels a fill and never credits a
                    // closure the order could have reached by expiry.
                    self.confirmCancelBroadcast()
                    onStatus(.confirmed)
                    return
                case let .failed(reason):
                    // The chain refused the cancel. Withdraw the record so the
                    // order drops out of `.cancelling` back to `.pending` and its
                    // Cancel button goes live again — the user has to be able to
                    // retry, and the chain's own words are the only explanation
                    // of why they must.
                    self.revertCancelBroadcast()
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

    /// Move the order into `.cancelling` and store the cancel hash, on the
    /// strength of this confirmed broadcast.
    ///
    /// The store's `recordCancelBroadcast` is compare-and-set on a non-terminal
    /// order, so a race — the order filled or expired between the tap and this
    /// call — is a no-op rather than a resurrection, and re-recording the same
    /// transaction is idempotent.
    ///
    /// Non-fatal on failure: the transaction went out regardless, and the worst
    /// case is the order not showing "Cancelling…" until the tracker's next poll
    /// reconciles it. Surfacing an error over a broadcast that succeeded would be
    /// the more misleading of the two.
    private func recordCancelBroadcast() {
        // A non-empty hash is what makes this a confirmed broadcast — the same
        // bar the verifier sets. An empty hash is no broadcast at all, and
        // recording `""` would enter `.cancelling` and block the button on a
        // cancel that never went out.
        guard !txHash.isEmpty else { return }
        do {
            try intents.recordCancelBroadcast(
                inboundTxHash: request.inboundTxHash,
                pubKeyECDSA: pubKeyECDSA,
                txHash: txHash
            )
        } catch {
            logger.warning("Failed to record cancel broadcast: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Mark the recorded cancel CONFIRMED on-chain, on the strength of a
    /// `.succeeded` (THORChain) or `.delivered` (L1) verdict.
    ///
    /// This is what lets a later no-reason refund be credited to the cancel; the
    /// broadcast record alone never can. Compare-and-set on the hash, and
    /// non-fatal on failure — the tracker's `verifyPendingCancel` confirms the
    /// same record independently.
    private func confirmCancelBroadcast() {
        do {
            try intents.confirmCancelBroadcast(
                inboundTxHash: request.inboundTxHash,
                pubKeyECDSA: pubKeyECDSA,
                txHash: txHash
            )
        } catch {
            logger.warning("Failed to confirm cancel broadcast: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Withdraw the record for a cancel the chain refused, returning the order to
    /// `.pending`.
    ///
    /// Compare-and-set on the hash we verified: a cancel recorded since is a
    /// different transaction this verdict says nothing about. Non-fatal on
    /// failure — the tracker's `verifyPendingCancel` re-checks and withdraws the
    /// same record independently.
    private func revertCancelBroadcast() {
        do {
            try intents.clearCancelBroadcast(
                inboundTxHash: request.inboundTxHash,
                pubKeyECDSA: pubKeyECDSA,
                expecting: txHash
            )
        } catch {
            logger.warning("Failed to withdraw the failed cancel record: \(error.localizedDescription, privacy: .public)")
        }
    }
}
