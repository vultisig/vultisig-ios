//
//  SendCryptoVerifyView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SendVerifyScreen: View {
    @StateObject var sendCryptoVerifyViewModel = SendCryptoVerifyViewModel()
    @ObservedObject var tx: SendTransaction
    let vault: Vault

    @State var fastPasswordPresented = false

    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.router) var router

    @State private var error: HelperError?

    var body: some View {
        Screen {
            VStack(spacing: 16) {
                fields
                pairedSignButton
            }
        }
        .screenTitle("verify".localized)
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
                await sendCryptoVerifyViewModel.loadGasInfoForSending(tx: tx)
                await sendCryptoVerifyViewModel.scan(transaction: tx, vault: vault)
            }
        }
        .onDisappear {
            sendCryptoVerifyViewModel.isLoading = false
            // Clear password if navigating back (not forward to keysign)
            if tx.fastVaultPassword.isNotEmpty {
                tx.fastVaultPassword = .empty
            }
        }
    }

    var fields: some View {
        SendCryptoVerifySummaryView(
            input: SendCryptoVerifySummary(
                fromName: vault.name,
                fromAddress: tx.fromAddress,
                toAddress: tx.toAddress,
                network: tx.coin.chain.name,
                networkImage: tx.coin.chain.logo,
                memo: tx.memo,
                feeCrypto: tx.isCalculatingFee ? "Loading..." : tx.gasInReadable,
                feeFiat: tx.isCalculatingFee ? "" : CryptoAmountFormatter.feesInReadable(tx: tx, vault: vault),
                isCalculatingFee: tx.isCalculatingFee,
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
                let result = try await sendCryptoVerifyViewModel.validateForm(
                    tx: tx,
                    vault: vault
                )
                await MainActor.run {
                    router.navigate(to: SendRoute.pairing(
                        vault: vault,
                        tx: tx,
                        keysignPayload: result,
                        fastVaultPassword: tx.fastVaultPassword.nilIfEmpty
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
                    tx.fastVaultPassword = .empty
                    onSignPress()
                }
                .crossPlatformSheet(isPresented: $fastPasswordPresented) {
                    FastVaultEnterPasswordView(
                        password: $tx.fastVaultPassword,
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

struct VerifyKeysignPayload: Identifiable, Hashable {
    let id: String
    let payload: KeysignPayload

    init(id: String = UUID().uuidString, payload: KeysignPayload) {
        self.id = id
        self.payload = payload
    }
}

#Preview {
    SendVerifyScreen(
        tx: SendTransaction(),
        vault: Vault.example
    )
    .environmentObject(SettingsViewModel())
}
