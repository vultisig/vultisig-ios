//
//  SendReviewContent.swift
//  VultisigApp
//
//  The send review, shown in the keysign review sheet over the screen that
//  built the transaction. Signing hands its route to the review presenter,
//  which pushes it once the sheet has closed.
//

import SwiftData
import SwiftUI

struct SendReviewContent: View {
    let retrySignal: SendRetrySignal
    let vault: Vault
    /// The presentation this review was shown under, handed back when it
    /// proceeds so a late sign step cannot proceed a later review.
    let presentationID: UUID

    @StateObject private var viewModel: SendCryptoVerifyViewModel
    @Environment(KeysignReviewPresenter.self) private var reviewPresenter

    @Query private var vaults: [Vault]
    @Query private var addressBookItems: [AddressBookItem]

    @State private var fastPasswordPresented = false
    @State private var error: HelperError?
    @State private var retryBannerText: String?
    @State private var isScanComplete = false

    init(
        transaction: SendTransaction,
        retrySignal: SendRetrySignal,
        vault: Vault,
        prebuiltKeysignPayload: KeysignPayload?,
        presentationID: UUID
    ) {
        _viewModel = StateObject(
            wrappedValue: SendCryptoVerifyViewModel(
                transaction: transaction,
                prebuiltKeysignPayload: prebuiltKeysignPayload
            )
        )
        self.retrySignal = retrySignal
        self.vault = vault
        self.presentationID = presentationID
    }

    private var tx: SendTransaction { viewModel.transaction }

    var body: some View {
        KeysignReviewSheet(
            title: "sendOverview".localized,
            scanRing: KeysignReviewScanRing(viewModel.securityScannerState, isScanComplete: isScanComplete),
            scanStatus: scanStatus,
            onClose: reviewPresenter.dismiss,
            onTapScanMark: revealScanStatus
        ) {
            SendReviewSummaryView(input: summary)
        } footer: {
            SendReviewFooter(
                isAmountCorrect: $viewModel.isAmountCorrect,
                isAddressCorrect: $viewModel.isAddressCorrect,
                isApproveCorrect: $viewModel.isApproveCorrect,
                isRippleTrustSet: isRippleTrustSet,
                isApproveRequired: viewModel.isApproveRequired,
                isFastVault: vault.offersFastSigning,
                isSignDisabled: viewModel.signButtonDisabled,
                onFastSign: { fastPasswordPresented = true },
                onPairedSign: {
                    viewModel.fastVaultPassword = ""
                    onSignPress()
                }
            )
        }
        .withBanner(text: $retryBannerText, style: .error)
        .alert(item: $error) { error in
            Alert(
                title: Text("error".localized),
                message: Text(error.localizedDescription.localized),
                dismissButton: .default(Text("ok".localized))
            )
        }
        .alert(isPresented: $viewModel.showAlert) {
            let title = Text("error".localized)
            let message = Text(viewModel.errorMessage.localized)
            // A failed load holds Sign until the figures on screen have been
            // resolved. `.onLoad` runs once, so without a way to re-run it here
            // a transient failure would strand the user with a disabled Sign.
            guard viewModel.hasLoadError else {
                return Alert(title: title, message: message,
                             dismissButton: .default(Text("ok".localized)))
            }
            return Alert(
                title: title,
                message: message,
                primaryButton: .default(Text("retry".localized)) {
                    Task { await viewModel.loadGasInfoForSending() }
                },
                secondaryButton: .cancel(Text("ok".localized))
            )
        }
        .onLoad {
            consumePendingRetry()
            viewModel.onLoad()
            Task {
                await viewModel.loadGasInfoForSending()
                await viewModel.scan()
                isScanComplete = true
            }
        }
        .onDisappear {
            viewModel.isLoading = false
            if viewModel.fastVaultPassword.isNotEmpty {
                viewModel.fastVaultPassword = ""
            }
        }
        .fastVaultPasswordSheet(
            isPresented: $fastPasswordPresented,
            password: $viewModel.fastVaultPassword,
            vault: vault,
            onSubmit: { onSignPress() }
        )
    }

    /// A retryable broadcast failure reopens this review. The load above
    /// re-fetches the fee, so all that is left is to say why it is back.
    private func consumePendingRetry() {
        guard let reason = retrySignal.pendingRetryReason else { return }
        retryBannerText = reason.userFacingMessage
        retrySignal.pendingRetryReason = nil
    }

    private var scanStatus: KeysignReviewScanStatus? {
        .forSecurityScanner(
            showSecurityScannerSheet: viewModel.showSecurityScannerSheet,
            result: viewModel.securityScannerState.result,
            isContinueAnywayDisabled: viewModel.signButtonDisabled,
            onDismiss: { viewModel.showSecurityScannerSheet = false },
            onContinueAnyway: {
                viewModel.showSecurityScannerSheet = false
                signAndProceed()
            }
        )
    }

    private func revealScanStatus() {
        viewModel.showSecurityScannerSheet = true
    }

    private var toAlias: String? {
        SendAddressResolver.resolveAlias(
            address: tx.toAddress,
            coinMeta: tx.coin.toCoinMeta(),
            ensLabel: tx.toAddressLabel,
            vaults: vaults,
            addressBookItems: addressBookItems
        )
    }

    private var summary: SendCryptoVerifySummary {
        SendCryptoVerifySummary(
            fromName: vault.name,
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            toAlias: toAlias,
            network: tx.coin.chain.name,
            networkImage: tx.coin.chain.logo,
            memo: tx.memo,
            destinationTag: tx.destinationTag.map(String.init),
            feeCrypto: viewModel.isCalculatingFee ? "loading".localized : tx.gasInReadable,
            feeFiat: viewModel.isCalculatingFee ? "" : CryptoAmountFormatter.feesInReadable(tx: tx),
            isCalculatingFee: viewModel.isCalculatingFee,
            coinImage: tx.coin.logo,
            amount: tx.amount,
            amountFiat: viewModel.amountFiat,
            coinTicker: tx.coin.ticker,
            keysignPayload: viewModel.verifyKeysignPayload,
            // Send-routed DeFi operations can supply a hero; plain sends remain nil.
            hero: TransactionHeroResolver.hero(on: .sendVerify, for: .initiating(tx)),
            rippleTrustSet: RippleTrustSetPresentation.state(for: tx)
        )
    }

    /// Read off the transaction rather than the payload: the payload is only
    /// built on confirm, and the checkboxes have to be right from the first
    /// render.
    private var isRippleTrustSet: Bool {
        tx.coin.chain == .ripple && tx.transactionType == .rippleTrustSet
    }

    private func onSignPress() {
        if viewModel.validateSecurityScanner() {
            signAndProceed()
        }
    }

    private func signAndProceed() {
        Task {
            do {
                let payload = try await viewModel.validateForm()
                await MainActor.run {
                    let context = SigningTxContext.send(vault: vault, tx: viewModel.transaction, retry: retrySignal)
                    let route = SigningRoute.afterReview(
                        context: context,
                        keysignPayload: payload,
                        fastVaultPassword: viewModel.fastVaultPassword
                    )
                    reviewPresenter.proceed(to: route, presentationID: presentationID)
                }
            } catch {
                await MainActor.run {
                    self.error = error as? HelperError
                }
            }
        }
    }
}

/// The send review's confirmations and sign buttons.
struct SendReviewFooter: View {
    @Binding var isAmountCorrect: Bool
    @Binding var isAddressCorrect: Bool
    @Binding var isApproveCorrect: Bool
    let isRippleTrustSet: Bool
    let isApproveRequired: Bool
    let isFastVault: Bool
    let isSignDisabled: Bool
    let onFastSign: () -> Void
    let onPairedSign: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                // An XRPL TrustSet sends nothing to anyone, so "the amount is
                // correct" / "I'm sending to the right address" are both false
                // framings. What the user confirms is the limit and the issuer.
                if isRippleTrustSet {
                    KeysignReviewCheckbox(isChecked: $isAmountCorrect, text: "rippleTrustLineLimitCheck")
                    KeysignReviewCheckbox(isChecked: $isAddressCorrect, text: "rippleTrustLineIssuerCheck")
                } else {
                    KeysignReviewCheckbox(isChecked: $isAmountCorrect, text: "correctAmountCheck")
                    KeysignReviewCheckbox(isChecked: $isAddressCorrect, text: "sendingRightAddressCheck")
                }
                if isApproveRequired {
                    KeysignReviewCheckbox(isChecked: $isApproveCorrect, text: "yieldVerifyApproveCheck")
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
