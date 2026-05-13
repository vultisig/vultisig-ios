//
//  SendCryptoVerifyView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftData
import SwiftUI

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

    init(transaction: SendTransaction, retrySignal: SendRetrySignal, vault: Vault) {
        _sendCryptoVerifyViewModel = StateObject(wrappedValue: SendCryptoVerifyViewModel(transaction: transaction))
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
            Alert(
                title: Text(NSLocalizedString("error", comment: "")),
                message: Text(NSLocalizedString(sendCryptoVerifyViewModel.errorMessage, comment: "")),
                dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
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
                feeCrypto: sendCryptoVerifyViewModel.isCalculatingFee ? "loading".localized : tx.gasInReadable,
                feeFiat: sendCryptoVerifyViewModel.isCalculatingFee ? "" : CryptoAmountFormatter.feesInReadable(tx: tx),
                isCalculatingFee: sendCryptoVerifyViewModel.isCalculatingFee,
                coinImage: tx.coin.logo,
                amount: tx.amount,
                coinTicker: tx.coin.ticker
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
            Checkbox(isChecked: $sendCryptoVerifyViewModel.isAmountCorrect, text: "correctAmountCheck")
            Checkbox(isChecked: $sendCryptoVerifyViewModel.isAddressCorrect, text: "sendingRightAddressCheck")
        }
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
                    router.navigate(to: SendRoute.pairing(
                        vault: vault,
                        tx: sendCryptoVerifyViewModel.transaction,
                        retrySignal: retrySignal,
                        keysignPayload: result,
                        fastVaultPassword: sendCryptoVerifyViewModel.fastVaultPassword.nilIfEmpty
                    ))
                }
            } catch {
                await MainActor.run {
                    self.error = error as? HelperError
                }
            }
        }
    }

    var pairedSignButton: some View {
        VStack {
            if tx.isFastVault {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)

                LongPressPrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {
                    fastPasswordPresented = true
                } longPressAction: {
                    // Clear password for paired sign (long press)
                    sendCryptoVerifyViewModel.fastVaultPassword = ""
                    onSignPress()
                }
                .crossPlatformSheet(isPresented: $fastPasswordPresented) {
                    FastVaultEnterPasswordView(
                        password: $sendCryptoVerifyViewModel.fastVaultPassword,
                        vault: vault,
                        onSubmit: { onSignPress() }
                    )
                }
            } else {
                PrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {
                    onSignPress()
                }
            }
        }
        .disabled(sendCryptoVerifyViewModel.signButtonDisabled)
    }
}
