//
//  SigningKeysignScreen.swift
//  VultisigApp
//
//  Single keysign screen for every keysign-side flow (Send, Swap,
//  FunctionCall; fast + paired). Replaces the four per-flow leaf screens
//  (Send/Swap x paired/fast). It mounts the shared `KeysignView` with the
//  `KeysignStartInput` the router built, and — driven by its
//  `SigningKeysignCoordinator` — dispatches the done route, the pop-to-verify
//  retry, and (swap only) `stopMediator` by `SigningTxContext`.
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "signing-keysign")

struct SigningKeysignScreen: View {
    @Environment(\.router) var router

    let source: KeysignStartInput
    let context: SigningTxContext
    @StateObject private var coordinator = SigningKeysignCoordinator()

    var body: some View {
        Screen {
            KeysignView(source: source, transferViewModel: coordinator)
        }
        .screenNavigationBarHidden()
        .screenEdgeInsets(.zero)
        .onChange(of: coordinator.keysignFinished) { _, finished in
            guard finished else { return }
            navigateToDone()
        }
        .onChange(of: coordinator.pendingRetryReason) { _, reason in
            guard let reason else { return }
            handleRetry(reason: reason)
        }
        .onDisappear {
            // Swap kept the mediator running through keysign and stopped it on
            // teardown; the send family never did. Preserve that per-flow.
            if case .swap = context {
                coordinator.stopMediator()
            }
        }
    }

    private func navigateToDone() {
        guard let hash = coordinator.hash else {
            logger.error("keysignFinished fired but coordinator.hash is nil; cannot navigate to done")
            return
        }

        switch context {
        case .send(let vault, let tx, _), .functionCall(let vault, let tx, _):
            // The signed payload (possibly bootstrap-refreshed) drives the chain
            // and the done payload, matching the former paired/fast Send screens.
            guard let payload = coordinator.resolvedKeysignPayload else {
                logger.error("keysignFinished fired but resolvedKeysignPayload is nil; cannot navigate to send done")
                return
            }
            router.navigate(to: SigningRoute.done(.send(
                vault: vault,
                hash: hash,
                chain: payload.coin.chain,
                tx: tx,
                keysignPayload: payload
            )))
        case .swap(let vaultPubKeyECDSA, let transaction, _):
            router.navigate(to: SigningRoute.done(.swap(
                vaultPubKeyECDSA: vaultPubKeyECDSA,
                hash: hash,
                approveHash: coordinator.approveHash,
                chain: transaction.fromCoin.chain,
                transaction: transaction,
                progressLink: transaction.progressLink(hash: hash)
            )))
        }
    }

    private func handleRetry(reason: BroadcastRetryReason) {
        // Thread the reason back into the flow's retry signal so the verify
        // screen re-surfaces it on reappear, then pop to that verify screen.
        switch context {
        case .send(_, _, let retry), .functionCall(_, _, let retry):
            retry.pendingRetryReason = reason
            coordinator.pendingRetryReason = nil
            router.navigateBackToKeysignVerify()
        case .swap(_, _, let retry):
            retry.pendingRetryReason = reason
            coordinator.pendingRetryReason = nil
            // Robust to deep-links that add routes before .root.
            router.navigateBack { destination in
                guard let route = destination as? SwapRoute else { return false }
                if case .verify = route { return true }
                return false
            }
        }
    }
}
