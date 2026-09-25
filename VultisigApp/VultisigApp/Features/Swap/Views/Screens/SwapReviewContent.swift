//
//  SwapReviewContent.swift
//  VultisigApp
//
//  The swap review, market and limit, shown in the keysign review sheet over
//  the swap form. Signing hands its route to the review presenter, which
//  pushes it once the sheet has closed.
//

import SwiftUI

struct SwapReviewContent: View {
    let retrySignal: SwapRetrySignal
    let vault: Vault
    /// The presentation this review was shown under, handed back when it
    /// proceeds so a late sign step cannot proceed a later review.
    let presentationID: UUID

    @State private var viewModel: SwapVerifyViewModel
    @Environment(KeysignReviewPresenter.self) private var reviewPresenter

    @State private var fastPasswordPresented = false
    @State private var fastVaultPassword: String = .empty
    @State private var signButtonDisabled = false
    @State private var signingTask: Task<Void, Never>?
    @State private var retryBannerText: String?
    @State private var isScanComplete = false

    init(transaction: SwapTransaction, retrySignal: SwapRetrySignal, vault: Vault, presentationID: UUID) {
        self.retrySignal = retrySignal
        self.vault = vault
        self.presentationID = presentationID
        _viewModel = State(initialValue: SwapVerifyViewModel(transaction: transaction))
    }

    private var transaction: SwapTransaction { viewModel.transaction }

    var body: some View {
        @Bindable var vm = viewModel
        KeysignReviewSheet(
            title: "swapOverview".localized,
            scanRing: KeysignReviewScanRing(viewModel.securityScannerState, isScanComplete: isScanComplete),
            scanStatus: scanStatus,
            onClose: reviewPresenter.dismiss,
            onTapScanMark: revealScanStatus
        ) {
            SwapReviewSummaryView(
                summary: SwapReviewSummary(transaction: transaction, vault: vault)
            )
        } footer: {
            SwapReviewFooter(
                isAmountCorrect: $vm.isAmountCorrect,
                isFeeCorrect: $vm.isFeeCorrect,
                isApproveCorrect: $vm.isApproveCorrect,
                isApproveRequired: transaction.isApproveRequired,
                isFastVault: vault.offersFastSigning,
                isSignDisabled: isSignDisabled,
                onFastSign: { fastPasswordPresented = true },
                onPairedSign: {
                    fastVaultPassword = .empty
                    onSignPress()
                }
            )
        } headerAccessory: {
            refreshCounter
        }
        .withLoading(isLoading: $vm.isLoadingFees)
        .withBanner(text: $retryBannerText, style: .error)
        .withBanner(text: $vm.routeSelectionNotice, style: .error)
        // Surface build-side failures so the user doesn't see "nothing
        // happens" after entering the fast vault password. `prepareSigning`
        // catches errors into `viewModel.error`.
        .alert(
            "error".localized,
            isPresented: Binding(
                get: { viewModel.error != nil },
                set: { isShown in if !isShown { viewModel.error = nil } }
            ),
            actions: {
                Button("ok".localized, role: .cancel) {}
            },
            message: {
                Text(viewModel.error?.localizedDescription ?? "")
            }
        )
        .swapRefreshTick {
            Task {
                await viewModel.updateTimer(vault: vault)
            }
        }
        .onLoad {
            viewModel.onLoad()
            Task {
                await viewModel.scan()
                isScanComplete = true
            }
            consumePendingRetry()
        }
        .onDisappear {
            signingTask?.cancel()
            signingTask = nil
            viewModel.isLoading = false
            fastVaultPassword = .empty
        }
        .fastVaultPasswordSheet(
            isPresented: $fastPasswordPresented,
            password: $fastVaultPassword,
            vault: vault,
            onSubmit: { onSignPress() }
        )
    }

    @ViewBuilder
    private var refreshCounter: some View {
        // A limit order executes at a fixed target price, so there is no live
        // quote to count down to.
        if !transaction.isLimit && !viewModel.isLoadingFees {
            SwapRefreshQuoteCounter(timer: viewModel.timer)
        }
    }

    private var scanStatus: KeysignReviewScanStatus? {
        .forSecurityScanner(
            showSecurityScannerSheet: viewModel.showSecurityScannerSheet,
            result: viewModel.securityScannerState.result,
            isContinueAnywayDisabled: isSignDisabled,
            onDismiss: { viewModel.showSecurityScannerSheet = false },
            onContinueAnyway: {
                viewModel.showSecurityScannerSheet = false
                signAndProceed()
            }
        )
    }

    /// The exact predicate `SigningCTAButtons` disables Sign on, reused so
    /// "Continue anyway" can never sign something Sign itself would refuse.
    private var isSignDisabled: Bool {
        !viewModel.canStartSigning || signButtonDisabled
    }

    private func revealScanStatus() {
        viewModel.showSecurityScannerSheet = true
    }

    /// A retryable broadcast failure reopens this review with a fresh quote.
    private func consumePendingRetry() {
        guard let reason = retrySignal.pendingRetryReason else { return }
        retryBannerText = reason.userFacingMessage
        retrySignal.pendingRetryReason = nil
        Task {
            await viewModel.refreshData(vault: vault)
        }
    }

    private func onSignPress() {
        guard viewModel.canStartSigning, !signButtonDisabled else { return }
        if viewModel.validateSecurityScanner() {
            signAndProceed()
        }
    }

    private func signAndProceed() {
        guard viewModel.canStartSigning, !signButtonDisabled else { return }
        signButtonDisabled = true
        let password = fastVaultPassword.nilIfEmpty
        signingTask = Task { @MainActor in
            defer {
                signButtonDisabled = false
                signingTask = nil
            }
            guard let prepared = await viewModel.prepareSigning(vault: vault, retrySignal: retrySignal) else { return }
            defer { viewModel.finishSigning() }
            guard !Task.isCancelled else { return }
            // Preparation froze the transaction for the payload and everything
            // after it; the live display state is not read again.
            let route = SigningRoute.afterReview(
                context: prepared.context,
                keysignPayload: prepared.payload,
                fastVaultPassword: password ?? ""
            )
            reviewPresenter.proceed(to: route, presentationID: presentationID)
        }
    }
}

/// The swap review's confirmations and sign buttons.
struct SwapReviewFooter: View {
    @Binding var isAmountCorrect: Bool
    @Binding var isFeeCorrect: Bool
    @Binding var isApproveCorrect: Bool
    let isApproveRequired: Bool
    let isFastVault: Bool
    let isSignDisabled: Bool
    let onFastSign: () -> Void
    let onPairedSign: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                KeysignReviewCheckbox(isChecked: $isAmountCorrect, text: "swapVerifyCheckbox1Description")
                KeysignReviewCheckbox(isChecked: $isFeeCorrect, text: "swapVerifyCheckbox2Description")
                if isApproveRequired {
                    KeysignReviewCheckbox(isChecked: $isApproveCorrect, text: "swapVerifyCheckbox3Description")
                }
            }

            SigningCTAButtons(
                isFastVault: isFastVault,
                isDisabled: isSignDisabled,
                singleSignTitle: "signTransaction",
                onFastSign: onFastSign,
                onPairedSign: onPairedSign
            )
        }
    }
}
