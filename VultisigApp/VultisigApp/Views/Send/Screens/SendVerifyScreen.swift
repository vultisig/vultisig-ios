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
    
    var body: some View {
        Screen(title: "verify") {
            VStack(spacing: 16) {
                fields
                pairedSignButton
            }
            .blur(radius: sendCryptoVerifyViewModel.isLoading ? 1 : 0)
        }
        .gesture(DragGesture())
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
            securityScannerState: $sendCryptoVerifyViewModel.securityScannerState,
            contentPadding: 16
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
        
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            Task {
                let keysignPayload = await sendCryptoVerifyViewModel.validateForm(
                    tx: tx,
                    vault: vault
                )
                
                guard let keysignPayload else { return }
                router.navigate(
                    to: SendRoute.pairing(
                        vault: vault,
                        tx: tx,
                        keysignPayload: keysignPayload,
                        fastVaultPassword: tx.fastVaultPassword.nilIfEmpty
                    )
                )
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
        .disabled(!sendCryptoVerifyViewModel.isValidForm)
        .padding(.horizontal, 16)
//        .padding(.bottom, idiom == .pad ? 30 : 0)
    }
}

#Preview {
    SendVerifyScreen(
        sendCryptoVerifyViewModel: SendCryptoVerifyViewModel(),
        tx: SendTransaction(),
        vault: Vault.example
    )
    .environmentObject(SettingsViewModel())
}
