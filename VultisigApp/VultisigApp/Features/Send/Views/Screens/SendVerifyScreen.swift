//
//  SendCryptoVerifyView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftData
import SwiftUI
import VultisigCommonData

struct SendVerifyScreen: View {
    @StateObject private var sendCryptoVerifyViewModel: SendCryptoVerifyViewModel
    let retrySignal: SendRetrySignal
    let vault: Vault

    @Query private var vaults: [Vault]
    @Query private var addressBookItems: [AddressBookItem]

    @State private var fastPasswordPresented = false

    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.router) var router

    @State private var error: HelperError?
    @State private var retryBannerText: String?

    init(transaction: SendTransaction, retrySignal: SendRetrySignal, vault: Vault, prebuiltKeysignPayload: KeysignPayload? = nil) {
        _sendCryptoVerifyViewModel = StateObject(
            wrappedValue: SendCryptoVerifyViewModel(
                transaction: transaction,
                prebuiltKeysignPayload: prebuiltKeysignPayload
            )
        )
        self.retrySignal = retrySignal
        self.vault = vault
    }

    private var tx: SendTransaction { sendCryptoVerifyViewModel.transaction }

    var body: some View {
        Screen {
            VStack(spacing: 16) {
                fields
                pairedSignButton
            }
        }
        .screenTitle("verify".localized)
        .withBanner(text: $retryBannerText, style: .error)
        .alert(item: $error) { error in
            Alert(
                title: Text(NSLocalizedString("error", comment: "")),
                message: Text(NSLocalizedString(error.localizedDescription, comment: "")),
                dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
            )
        }
        .alert(isPresented: $sendCryptoVerifyViewModel.showAlert) {
            let title = Text(NSLocalizedString("error", comment: ""))
            let message = Text(NSLocalizedString(sendCryptoVerifyViewModel.errorMessage, comment: ""))
            // A failed load holds Sign until the figures on screen have been
            // resolved. `.onLoad` runs once, so without a way to re-run it here
            // a transient failure would strand the user with a disabled Sign
            // and no option but to back out of the flow.
            guard sendCryptoVerifyViewModel.hasLoadError else {
                return Alert(title: title, message: message,
                             dismissButton: .default(Text(NSLocalizedString("ok", comment: ""))))
            }
            return Alert(
                title: title,
                message: message,
                primaryButton: .default(Text(NSLocalizedString("retry", comment: ""))) {
                    Task { await sendCryptoVerifyViewModel.loadGasInfoForSending() }
                },
                secondaryButton: .cancel(Text(NSLocalizedString("ok", comment: "")))
            )
        }
        .onLoad {
            sendCryptoVerifyViewModel.onLoad()
            Task {
                await sendCryptoVerifyViewModel.loadGasInfoForSending()
                await sendCryptoVerifyViewModel.scan()
            }
        }
        .onNavigationStackChange { isVisible in
            if isVisible {
                consumePendingRetry()
            }
        }
        .onDisappear {
            sendCryptoVerifyViewModel.isLoading = false
            // Clear password if navigating back (not forward to keysign)
            if sendCryptoVerifyViewModel.fastVaultPassword.isNotEmpty {
                sendCryptoVerifyViewModel.fastVaultPassword = ""
            }
        }
    }

    private func consumePendingRetry() {
        guard let reason = retrySignal.pendingRetryReason else { return }
        retryBannerText = reason.userFacingMessage
        retrySignal.pendingRetryReason = nil
        Task {
            await sendCryptoVerifyViewModel.loadGasInfoForSending()
        }
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

    var fields: some View {
        SendCryptoVerifySummaryView(
            input: SendCryptoVerifySummary(
                fromName: vault.name,
                fromAddress: tx.fromAddress,
                toAddress: tx.toAddress,
                toAlias: toAlias,
                network: tx.coin.chain.name,
                networkImage: tx.coin.chain.logo,
                memo: tx.memo,
                destinationTag: tx.destinationTag.map(String.init),
                feeCrypto: sendCryptoVerifyViewModel.isCalculatingFee ? "loading".localized : tx.gasInReadable,
                feeFiat: sendCryptoVerifyViewModel.isCalculatingFee ? "" : CryptoAmountFormatter.feesInReadable(tx: tx),
                isCalculatingFee: sendCryptoVerifyViewModel.isCalculatingFee,
                coinImage: tx.coin.logo,
                amount: tx.amount,
                amountFiat: sendCryptoVerifyViewModel.amountFiat,
                coinTicker: tx.coin.ticker,
                keysignPayload: sendCryptoVerifyViewModel.verifyKeysignPayload,
                rippleTrustSet: RippleTrustSetPresentation.state(for: tx)
            ),
            securityScannerState: $sendCryptoVerifyViewModel.securityScannerState
        ) {
            checkboxes
        }
        .bottomSheet(isPresented: $sendCryptoVerifyViewModel.showSecurityScannerSheet) {
            SecurityScannerBottomSheet(securityScannerModel: sendCryptoVerifyViewModel.securityScannerState.result) {
                sendCryptoVerifyViewModel.showSecurityScannerSheet = false
                signAndMoveToNextView()
            } onDismissRequest: {
                sendCryptoVerifyViewModel.showSecurityScannerSheet = false
            }
        }
    }

    var checkboxes: some View {
        VStack(spacing: 16) {
            // An XRPL TrustSet sends nothing to anyone, so "the amount is
            // correct" / "I'm sending to the right address" are both false
            // framings. What the user is confirming is the limit and the issuer.
            if isRippleTrustSet {
                Checkbox(isChecked: $sendCryptoVerifyViewModel.isAmountCorrect, text: "rippleTrustLineLimitCheck")
                Checkbox(isChecked: $sendCryptoVerifyViewModel.isAddressCorrect, text: "rippleTrustLineIssuerCheck")
            } else {
                Checkbox(isChecked: $sendCryptoVerifyViewModel.isAmountCorrect, text: "correctAmountCheck")
                Checkbox(isChecked: $sendCryptoVerifyViewModel.isAddressCorrect, text: "sendingRightAddressCheck")
            }
            if sendCryptoVerifyViewModel.isApproveRequired {
                Checkbox(isChecked: $sendCryptoVerifyViewModel.isApproveCorrect, text: "yieldVerifyApproveCheck")
            }
        }
    }

    /// Read off the transaction rather than the payload: the payload is only built
    /// on confirm, and the checkboxes have to be right from the first render.
    private var isRippleTrustSet: Bool {
        tx.coin.chain == .ripple && tx.transactionType == .rippleTrustSet
    }

    func onSignPress() {
        let canSign = sendCryptoVerifyViewModel.validateSecurityScanner()
        if canSign {
            signAndMoveToNextView()
        }
    }

    func signAndMoveToNextView() {
        Task {
            do {
                let result = try await sendCryptoVerifyViewModel.validateForm()
                await MainActor.run {
                    // Fast vaults sign server-side with no peer to pair with,
                    // so route straight into keysign (the bootstrap runs there)
                    // and never mount the pairing screen. A present fast
                    // password is the fast-sign signal; an empty one means the
                    // user chose paired-sign, which keeps the QR pairing screen.
                    let context = SigningTxContext.send(
                        vault: vault,
                        tx: sendCryptoVerifyViewModel.transaction,
                        retry: retrySignal
                    )
                    if let fastPassword = sendCryptoVerifyViewModel.fastVaultPassword.nilIfEmpty {
                        router.navigate(to: SigningRoute.keysign(.fast(
                            context: context,
                            keysignPayload: result,
                            fastVaultPassword: fastPassword
                        )))
                    } else {
                        router.navigate(to: SigningRoute.pair(
                            context: context,
                            keysignPayload: result,
                            fastVaultPassword: nil
                        ))
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error as? HelperError
                }
            }
        }
    }

    var pairedSignButton: some View {
        SigningCTAButtons(
            isFastVault: vault.isFastVault,
            isDisabled: sendCryptoVerifyViewModel.signButtonDisabled,
            singleSignTitle: "signTransaction",
            onFastSign: { fastPasswordPresented = true },
            onPairedSign: {
                sendCryptoVerifyViewModel.fastVaultPassword = ""
                onSignPress()
            }
        )
        .crossPlatformSheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $sendCryptoVerifyViewModel.fastVaultPassword,
                vault: vault,
                onSubmit: { onSignPress() }
            )
        }
    }
}
