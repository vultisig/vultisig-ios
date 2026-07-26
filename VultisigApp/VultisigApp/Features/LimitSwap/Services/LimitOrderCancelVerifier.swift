//
//  LimitOrderCancelVerifier.swift
//  VultisigApp
//
//  Did the transaction carrying a cancel actually SUCCEED on its own chain?
//
//  This exists because a broadcast hash proves nothing. The 2026-07-21 mainnet
//  rehearsal returned a hash, was included in a block, and was REJECTED by
//  THORChain's handler with `could not find matching limit swap`. Treating the
//  hash as the outcome recorded a cancel that never happened — which disabled
//  the button for good and left a later closure ready to be labelled
//  "Cancelled".
//
//  ⚠️ Success here means "the chain accepted the message", not "the order is
//  gone". Only the queue can say the order actually closed, and it says so by
//  the order disappearing. What this rules out is the failure the queue can
//  never report: a cancel the chain refused.
//

import Foundation
import OSLog

/// The on-chain fate of a cancel transaction.
enum LimitOrderCancelTxOutcome: Equatable, Sendable {
    /// THORChain EXECUTED the modify message: `code == 0`, which for `m=<` means
    /// the handler found a matching resting order. The strongest answer
    /// available anywhere, and the exact thing the rejected rehearsal proves is
    /// not implied by inclusion in a block.
    ///
    /// Only the THORChain route can produce this.
    case succeeded
    /// The transaction carrying the memo confirmed on its own L1 chain, and
    /// THORChain's verdict on it is NOT observable.
    ///
    /// ⚠️ Deliberately not folded into `succeeded`, because it is a weaker
    /// claim: it says the memo was delivered somewhere Bifrost can see it, not
    /// that the order was found. THORChain dispatches an L1 `m=<` from the
    /// observed-tx path in EndBlock, which produces no transaction result for a
    /// client to read — so at the moment of the cancel, a wrong-bucket attempt
    /// on this route really is silent, exactly as it appeared to be on
    /// THORChain before the 2026-07-21 rehearsal proved otherwise there.
    ///
    /// It is not silent forever, though, and that distinction is worth keeping
    /// straight: if the cancel DID match, the order's eventual closure carries
    /// THORChain's own `limit swap cancelled` through Midgard's refund action,
    /// and the tracker reads it. What this route cannot answer is the question
    /// asked HERE and NOW — was the message accepted — which is exactly why the
    /// weaker case exists.
    case delivered
    /// The chain refused it, with its own reason.
    case failed(reason: String)
    /// Not answerable yet: not mined, not indexed, or the lookup itself failed.
    ///
    /// NOT a verdict. Every caller must ask again rather than treat this as
    /// either outcome — reading it as failure would clear a good cancel record,
    /// reading it as success would reinstate the bug this file exists for.
    case unresolved
}

@MainActor
protocol LimitOrderCancelVerifying {
    func verifyCancelTransaction(txHash: String, chain: Chain) async -> LimitOrderCancelTxOutcome
}

@MainActor
struct LimitOrderCancelVerifier: LimitOrderCancelVerifying {
    private let httpClient: HTTPClientProtocol
    private let statusChecker: TransactionStatusChecking
    private let logger = Logger(subsystem: "com.vultisig.app", category: "limit-cancel-verifier")

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        statusChecker: TransactionStatusChecking = TransactionStatusService.shared
    ) {
        self.httpClient = httpClient
        self.statusChecker = statusChecker
    }

    func verifyCancelTransaction(txHash: String, chain: Chain) async -> LimitOrderCancelTxOutcome {
        guard !txHash.isEmpty else { return .unresolved }
        if chain == .thorChain {
            return await verifyThorchainDeposit(txHash: txHash)
        }
        return await verifyL1Transaction(txHash: txHash, chain: chain)
    }

    /// The THORChain route, read from the Cosmos tx endpoint rather than through
    /// `TransactionStatusService`.
    ///
    /// ⚠️ **Not a preference — the shared path cannot answer this question.**
    /// `THORChainTransactionStatusProvider` reads Midgard ACTIONS, and a
    /// `MsgDeposit` whose handler rejects the message emits no action, so
    /// Midgard reports "no actions" indefinitely. A rejected cancel would sit at
    /// `.unresolved` forever and never be corrected. `code` + `raw_log` are the
    /// only place the refusal is visible at all.
    private func verifyThorchainDeposit(txHash: String) async -> LimitOrderCancelTxOutcome {
        do {
            let response = try await httpClient.request(
                ThorchainMainnetAPI(.transaction(hash: txHash)),
                responseType: CosmosTransactionStatusResponse.self
            )
            // No `tx_response` on a 200 means the node answered about a
            // transaction it has not indexed yet.
            guard let txResponse = response.data.txResponse else { return .unresolved }
            guard txResponse.code == 0 else {
                let reason = txResponse.rawLog?.trimmedNonEmpty
                    ?? "limitSwap.cancel.error.rejected".localized
                logger.error("Cancel tx \(txHash, privacy: .public) rejected: code \(txResponse.code)")
                return .failed(reason: reason)
            }
            return .succeeded
        } catch {
            // A 404 (not indexed yet), a rate limit, a timeout — none of these
            // is an on-chain result.
            logger.debug("Cancel tx lookup failed for \(txHash, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .unresolved
        }
    }

    /// Every other source chain, through the shared per-chain status providers.
    ///
    /// ⚠️ Narrower than it looks, which is why a confirmation here is
    /// `.delivered` and never `.succeeded`: it reports whether the DUST TRANSFER
    /// carrying the memo confirmed on its own chain, a precondition for the
    /// cancel rather than a confirmation of it. THORChain dispatches an L1 `m=<`
    /// from Bifrost's observed-tx path in EndBlock, and nothing there is
    /// readable from a client — so on this route the order leaving the queue
    /// remains the only evidence the cancel did anything.
    private func verifyL1Transaction(txHash: String, chain: Chain) async -> LimitOrderCancelTxOutcome {
        do {
            let result = try await statusChecker.checkTransactionStatus(txHash: txHash, chain: chain)
            switch result.status {
            case .confirmed:
                return .delivered
            case let .failed(reason):
                return .failed(reason: reason)
            case .pending, .notFound:
                return .unresolved
            }
        } catch {
            logger.debug("Cancel tx status failed for \(txHash, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .unresolved
        }
    }
}
