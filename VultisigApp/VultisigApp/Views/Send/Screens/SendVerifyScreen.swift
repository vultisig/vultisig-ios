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
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.router) var router
    
    @State private var keysignPayload: KeysignPayload?
    
    var body: some View {
        Screen(title: "verify".localized) {
            VStack(spacing: 16) {
                fields
                pairedSignButton
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
            print("SendVerifyScreen onDisappear")
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
        guard !isButtonDisabled else {
            return
        }
        
        isButtonDisabled = true
        sendCryptoVerifyViewModel.isLoading = true
        
        Task {
            let result = await sendCryptoVerifyViewModel.validateForm(
                tx: tx,
                vault: vault
            )
            await MainActor.run {
                if let payload = result {
                    // Navigate; onDisappear will clear loading.
                    self.keysignPayload = payload
                }
                // Validation failed — re-enable UI and stop loading.
                self.isButtonDisabled = false
                self.sendCryptoVerifyViewModel.isLoading = false
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
