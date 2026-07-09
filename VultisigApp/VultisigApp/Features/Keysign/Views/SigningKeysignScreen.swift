//
//  SigningKeysignScreen.swift
//  VultisigApp
//
//  Single container for every keysign-side flow (Send, Swap, FunctionCall;
//  fast + paired). It mounts the shared `KeysignView` while signing and — once
//  its `SigningKeysignCoordinator` reports a broadcastable result — crossfades
//  in place to the flow's `DoneScreen`, built inline from `context` (the
//  `SendTransaction`/`SwapTransaction`) + `coordinator` (`hash`/`approveHash`/
//  `resolvedKeysignPayload`). Keysign progress → broadcasted → pending →
//  result reads as one continuous screen instead of a NavigationStack push.
//  The container also dispatches the pop-to-verify retry and (swap only)
//  `stopMediator` by `SigningTxContext`.
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
        ZStack {
            if coordinator.keysignFinished {
                doneView
                    .transition(.opacity)
            } else {
                keysignView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: coordinator.keysignFinished)
        .onChange(of: coordinator.keysignFinished) { _, finished in
            guard finished else { return }
            handleKeysignFinished()
        }
        .onChange(of: coordinator.pendingRetryReason) { _, reason in
            guard let reason else { return }
            handleRetry(reason: reason)
        }
        .onDisappear {
            // Swap kept the mediator running through keysign and stopped it on
            // teardown; the send family never did. The finished path already
            // stopped it at the crossfade, so only cover backing out before
            // signing completes here (avoids a redundant second stop).
            if case .swap = context, !coordinator.keysignFinished {
                coordinator.stopMediator()
            }
        }
    }

    // MARK: - Branches

    private var keysignView: some View {
        Screen {
            KeysignView(source: source, transferViewModel: coordinator)
        }
        .screenNavigationBarHidden()
        .screenEdgeInsets(.zero)
    }

    /// The signing vault, resolved live at the screen boundary. Both `.ready`
    /// and `.fast` sources carry it (the router already resolved swap's live
    /// `@Model` from `pubKeyECDSA` before building this screen), so the swap
    /// done surface reuses it rather than re-fetching.
    private var sourceVault: Vault {
        switch source {
        case .ready(let input): return input.vault
        case .fast(let vault, _, _, _): return vault
        }
    }

    @ViewBuilder
    private var doneView: some View {
        switch context {
        case .send(let vault, let tx, _), .functionCall(let vault, let tx, _):
            sendDone(vault: vault, tx: tx)
        case .swap(_, let transaction, _):
            swapDone(transaction: transaction)
        }
    }

    @ViewBuilder
    private func sendDone(vault: Vault, tx: SendTransaction) -> some View {
        if let hash = coordinator.hash, let payload = coordinator.resolvedKeysignPayload {
            // The signed payload (possibly bootstrap-refreshed) drives the chain
            // and the done payload, matching the former paired/fast Send screens.
            SendDoneScreen(
                vault: vault,
                hash: hash,
                chain: payload.coin.chain,
                tx: tx,
                keysignPayload: payload
            )
        }
    }

    @ViewBuilder
    private func swapDone(transaction: SwapTransaction) -> some View {
        if let hash = coordinator.hash {
            SwapDoneScreen(
                vault: sourceVault,
                hash: hash,
                approveHash: coordinator.approveHash,
                chain: transaction.fromCoin.chain,
                transaction: transaction,
                progressLink: transaction.progressLink(hash: hash)
            )
        }
    }

    // MARK: - Coordinator handoff

    private func handleKeysignFinished() {
        // Diagnostics: the crossfade shows a blank done surface if the
        // coordinator handed us an incomplete result — log the same nil paths
        // the former done route logged.
        if coordinator.hash == nil {
            logger.error("keysignFinished fired but coordinator.hash is nil; done surface will be blank")
        }
        switch context {
        case .send, .functionCall:
            if coordinator.resolvedKeysignPayload == nil {
                logger.error("keysignFinished fired but resolvedKeysignPayload is nil; send done surface will be blank")
            }
        case .swap:
            // Swap stopped the relay session as the overview took over (the
            // former .done push point); keep that timing now that the overview
            // crossfades in place.
            coordinator.stopMediator()
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
