//
//  SigningKeysignScreen.swift
//  VultisigApp
//
//  Single container for every keysign-side flow (Send, Swap, FunctionCall;
//  fast + paired). It owns the `KeysignViewModel`, mounts the shared
//  `KeysignView` (pure signing animation) while signing and — once the
//  ceremony reaches `.KeysignFinished` — crossfades in place to the flow's
//  `DoneScreen`, built inline from `context` (the `SendTransaction`/
//  `SwapTransaction`) + the view-model (`txid`/`approveTxid`/`keysignPayload`).
//  Keysign progress -> broadcasted -> pending -> result reads as one
//  continuous screen instead of a NavigationStack push. The container also
//  dispatches the retry (via `KeysignView`'s `onRetry`), which pops back to
//  the screen that opened the review and reopens the review over it, and
//  (swap only) `Mediator.shared.stop()` by `SigningTxContext`.
//

import Mediator
import OSLog
import SwiftUI

private let logger = Log.keysign.view

struct SigningKeysignScreen: View {
    @Environment(\.router) var router
    @Environment(KeysignReviewPresenter.self) private var reviewPresenter

    let source: KeysignStartInput
    let context: SigningTxContext
    /// The keysign ceremony view-model, created once per signing session and
    /// handed to `KeysignView`. The container reads its `status` (crossfade
    /// gate) and `txid`/`approveTxid`/`keysignPayload` (done payload) directly.
    @StateObject private var keysignVM = KeysignViewModel()

    /// The ceremony broadcasts and reaches `.KeysignFinished` on success (for
    /// both roles); the done data (`txid` etc.) is already set by then. Failure
    /// / retry / unconfirmed states never reach `.KeysignFinished`, so they stay
    /// in `KeysignView` and never crossfade to Done.
    private var keysignFinished: Bool {
        keysignVM.status == .KeysignFinished
    }

    var body: some View {
        ZStack {
            if keysignFinished {
                doneView
                    .transition(.opacity)
            } else {
                keysignView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: keysignFinished)
        .onChange(of: keysignVM.status) { _, status in
            guard status == .KeysignFinished else { return }
            handleKeysignFinished()
        }
        .onDisappear {
            // Swap kept the mediator running through keysign and stopped it on
            // teardown; the send family never did. The finished path already
            // stopped it at the crossfade, so only cover backing out before
            // signing completes here (avoids a redundant second stop).
            if case .swap = context, !keysignFinished {
                Mediator.shared.stop()
            }
        }
    }

    // MARK: - Branches

    private var keysignView: some View {
        Screen {
            KeysignView(
                viewModel: keysignVM,
                source: source,
                onRetry: { reason in handleRetry(reason: reason) }
            )
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
        if !keysignVM.txid.isEmpty, let payload = keysignVM.keysignPayload {
            // The signed payload (possibly bootstrap-refreshed) drives the chain
            // and the done payload, matching the former paired/fast Send screens.
            SendDoneScreen(
                vault: vault,
                hash: keysignVM.txid,
                chain: payload.coin.chain,
                tx: tx,
                keysignPayload: payload
            )
        }
    }

    @ViewBuilder
    private func swapDone(transaction: SwapTransaction) -> some View {
        if !keysignVM.txid.isEmpty {
            SwapDoneScreen(
                vault: sourceVault,
                hash: keysignVM.txid,
                approveHash: keysignVM.approveTxid,
                chain: transaction.fromCoin.chain,
                transaction: transaction,
                progressLink: transaction.progressLink(hash: keysignVM.txid)
            )
        }
    }

    // MARK: - Finished / retry handling

    private func handleKeysignFinished() {
        // Done is the end of the flow; there is no review left to retry.
        reviewPresenter.flowFinished()
        // Diagnostics: the crossfade shows a blank done surface if the ceremony
        // finished without the expected data — log the same nil paths the former
        // done route logged.
        if keysignVM.txid.isEmpty {
            logger.error("keysign finished but txid is empty; done surface will be blank")
        }
        switch context {
        case .send, .functionCall:
            if keysignVM.keysignPayload == nil {
                logger.error("keysign finished but keysignPayload is nil; send done surface will be blank")
            }
        case .swap:
            // Swap stopped the relay session as the overview took over (the
            // former .done push point); keep that timing now that the overview
            // crossfades in place.
            Mediator.shared.stop()
        }
    }

    private func handleRetry(reason: BroadcastRetryReason) {
        // Thread the reason back into the flow's retry signal, which the
        // reopened review shows, then leave the signing screens for the one
        // that opened the review and bring the review back over it.
        switch context {
        case .send(_, _, let retry), .functionCall(_, _, let retry):
            retry.pendingRetryReason = reason
        case .swap(_, _, let retry):
            retry.pendingRetryReason = reason
        }
        router.navigateBackOutOfSigning()
        reviewPresenter.reopenForRetry()
    }
}
