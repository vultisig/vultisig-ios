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
    
    @State var isButtonDisabled = false
    @State var fastPasswordPresented = false
    @State var lastTapTime: Date = Date.distantPast
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.router) var router
    
    @State private var keysignPayload: KeysignPayload?
    
    var body: some View {
        Screen(title: "verify".localized) {
            VStack(spacing: 16) {
                fields
                pairedSignButton
                
                // Loading indicator for validation
                if sendCryptoVerifyViewModel.isLoading {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Validating transaction...")
                            .font(Theme.fonts.bodySRegular)
                            .foregroundColor(Theme.colors.textPrimary)
                    }
                    .padding(.top, 8)
                }
            }
            .blur(radius: sendCryptoVerifyViewModel.isLoading ? 1 : 0)
        }
        .alert(isPresented: $sendCryptoVerifyViewModel.showAlert) {
            alert
        }
        .onLoad {
            sendCryptoVerifyViewModel.onLoad()
            Task {
                await sendCryptoVerifyViewModel.scan(transaction: tx, vault: vault)
            }
        }
        .onDisappear {
            sendCryptoVerifyViewModel.isLoading = false
        }
        .onAppear {
            setData()
        }
        .navigationDestination(item: $keysignPayload) { payload in
            SendRouteBuilder().buildPairScreen(
                vault: vault,
                tx: tx,
                keysignPayload: payload,
                fastVaultPassword: tx.fastVaultPassword.nilIfEmpty
            )
        }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(sendCryptoVerifyViewModel.errorMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
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
                feeCrypto: tx.gasInReadable,
                feeFiat: CryptoAmountFormatter.feesInReadable(tx: tx, vault: vault),
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
    
    private func setData() {
        isButtonDisabled = false
    }
    
    func onSignPress() {
        let canSign = sendCryptoVerifyViewModel.validateSecurityScanner()
        if canSign {
            signAndMoveToNextView()
        }
    }
    
    func signAndMoveToNextView() {
        // Debounce rapid taps (prevent multiple taps within 1 second)
        let now = Date()
        guard now.timeIntervalSince(lastTapTime) > 1.0 else {
            return
        }
        lastTapTime = now
        
        guard !isButtonDisabled else {
            return
        }
        
        // Immediately disable button and show loading
        isButtonDisabled = true
        sendCryptoVerifyViewModel.isLoading = true
        
        // Run validation but with proper UI feedback
        Task {
            let result = await sendCryptoVerifyViewModel.validateForm(
                tx: tx,
                vault: vault
            )
            await MainActor.run {
                if let payload = result {
                    // Validation successful - navigate
                    self.keysignPayload = payload
                } else {
                    // Validation failed - show error and re-enable button
                    self.isButtonDisabled = false
                    self.sendCryptoVerifyViewModel.isLoading = false
                    // Error is already shown by the viewModel
                }
            }
        }
    }
    
    var pairedSignButton: some View {
        VStack {
            if tx.isFastVault {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(Theme.colors.textExtraLight)
                    .font(Theme.fonts.bodySMedium)
                
                LongPressPrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {
                    fastPasswordPresented = true
                } longPressAction: {
                    onSignPress()
                }
                .sheet(isPresented: $fastPasswordPresented) {
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
        .disabled(!sendCryptoVerifyViewModel.isValidForm || isButtonDisabled)
    }
}

#Preview {
    SendVerifyScreen(
        tx: SendTransaction(),
        vault: Vault.example
    )
    .environmentObject(SettingsViewModel())
}
