//
//  FunctionCallVerifyView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI

struct FunctionCallVerifyView: View {
    @Binding var keysignPayload: KeysignPayload?
    @ObservedObject var depositViewModel: FunctionCallViewModel
    @ObservedObject var depositVerifyViewModel: FunctionCallVerifyViewModel
    @ObservedObject var tx: SendTransaction
    let vault: Vault
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    @State var fastPasswordPresented = false
    @State var isForReferral = false
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .gesture(DragGesture())
        .alert(isPresented: $depositVerifyViewModel.showAlert) {
            alert
        }
        .onDisappear {
            depositVerifyViewModel.isLoading = false
        }
    }
    
    var content: some View {
        VStack(spacing: 0) {
            if isForReferral {
                ReferralSendOverviewView(
                    sendTx: tx,
                    functionCallViewModel: depositViewModel,
                    functionCallVerifyViewModel: depositVerifyViewModel
                )
            } else {
                summary
            }
            
            Spacer()
            pairedSignButton
                .padding(.bottom, 40)
                .padding(.horizontal, 16)
        }
        .blur(radius: depositVerifyViewModel.isLoading ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(depositVerifyViewModel.errorMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    var summary: some View {
        SendCryptoVerifySummaryView(
            input: SendCryptoVerifySummary(
                fromName: vault.name,
                fromAddress: tx.fromAddress,
                toAddress: tx.toAddress,
                network: tx.coin.chain.name,
                networkImage: tx.coin.chain.logo,
                memo: "",
                memoFunctionDictionary: depositViewModel.memoDictionary(for: tx.memoFunctionDictionary),
                feeCrypto: tx.gasInReadable,
                feeFiat: depositViewModel.feesInReadable(tx: tx, vault: vault),
                coinImage: tx.coin.logo,
                amount: getAmount(),
                coinTicker: tx.coin.ticker,
                showScannedBy: false
            )
        ) {}
        .padding(.horizontal, 16)
    }
    
    var pairedSignButton: some View {
        VStack {
            if tx.isFastVault {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(.extraLightGray)
                    .font(.body14BrockmannMedium)
                
                PrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {}
                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                        handleSubmit()
                    })
                    .simultaneousGesture(TapGesture().onEnded { _ in
                        fastPasswordPresented = true
                    })
                    .sheet(isPresented: $fastPasswordPresented) {
                        FastVaultEnterPasswordView(
                            password: $tx.fastVaultPassword,
                            vault: vault,
                            onSubmit: { handleSubmit() }
                        )
                    }
            } else {
                PrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {
                    handleSubmit()
                }
            }
        }
    }
    
    private func getAmount() -> String {
        return tx.amountDecimal.formatForDisplay() + " " + tx.coin.ticker
    }
    
    private func handleSubmit() {
        Task {
            keysignPayload = await depositVerifyViewModel.createKeysignPayload(tx: tx, vault: vault)
            
            if keysignPayload != nil {
                depositViewModel.moveToNextView()
            }
        }
    }
}

#Preview {
    FunctionCallVerifyView(
        keysignPayload: .constant(nil),
        depositViewModel: FunctionCallViewModel(),
        depositVerifyViewModel: FunctionCallVerifyViewModel(),
        tx: SendTransaction(),
        vault: Vault.example
    )
    .environmentObject(SettingsViewModel())
}
