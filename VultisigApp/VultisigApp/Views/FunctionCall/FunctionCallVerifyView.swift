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
                ScrollView {
                    fields
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
                .blur(radius: depositVerifyViewModel.isLoading ? 1 : 0)
            }
            
            Spacer()
            VStack(spacing: 16) {
                if tx.isFastVault {
                    fastVaultButton
                }
                button
            }
            .padding(.bottom, 40)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    var fastVaultButton: some View {
        Button {
            fastPasswordPresented = true
        } label: {
            FilledButton(title: NSLocalizedString("fastSign", comment: ""))
        }
        .sheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $tx.fastVaultPassword,
                vault: vault,
                onSubmit: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        handleSubmit()
                    }
                }
            )
        }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString(depositVerifyViewModel.errorMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    var fields: some View {
        VStack(spacing: 30) {
            summary
        }
    }
    
    var summary: some View {
        VStack(spacing: 16) {
            getAddressCell(for: "from", with: tx.fromAddress)
            
            if tx.amountDecimal > 0 {
                Separator()
                getDetailsCell(for: "amount", with: getAmount())
            }
            
            if !tx.memoFunctionDictionary.allKeysInOrder().isEmpty {
                let validKeys = tx.memoFunctionDictionary.allKeysInOrder().filter { key in
                    guard let value = tx.memoFunctionDictionary.get(key) else { return false }
                    return !value.isEmpty && value != "0" && value != "0.0"
                }
                
                ForEach(Array(validKeys.enumerated()), id: \.element) { index, key in
                    if let value = tx.memoFunctionDictionary.get(key) {
                        if index > 0 || tx.amountDecimal > 0 || !tx.fromAddress.isEmpty {
                            Separator()
                        }
                        getAddressCell(for: key.toFormattedTitleCase(), with: value)
                    }
                }
            }
            
            Separator()
            getDetailsCell(for: "gas", with: tx.gasInReadable)
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var button: some View {
        Button {
            depositVerifyViewModel.isLoading = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                handleSubmit()
            }
            
        } label: {
            if tx.isFastVault {
                OutlineButton(title: "Paired sign")
            } else {
                FilledButton(title: "sign")
            }
        }
    }
    
    private func getAddressCell(for title: String, with address: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            
            Text(address)
                .font(.body12Menlo)
                .foregroundColor(.turquoise600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func getDetailsCell(for title: String, with value: String) -> some View {
        HStack {
            Text(
                NSLocalizedString(title, comment: "")
                    .replacingOccurrences(of: "Fiat", with: SettingsCurrency.current.rawValue)
            )
            Spacer()
            Text(value)
        }
        .font(.body16MenloBold)
        .foregroundColor(.neutral100)
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
