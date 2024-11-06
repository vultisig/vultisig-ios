//
//  DepositVerifyView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI

struct TransactionMemoVerifyView: View {
    @Binding var keysignPayload: KeysignPayload?
    @ObservedObject var depositViewModel: TransactionMemoViewModel
    @ObservedObject var depositVerifyViewModel: TransactionMemoVerifyViewModel
    @ObservedObject var tx: SendTransaction
    let vault: Vault
    
    @State var fastPasswordPresented = false

    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .gesture(DragGesture())
        .alert(isPresented: $depositVerifyViewModel.showAlert) {
            alert
        }
        .onDisappear {
            depositVerifyViewModel.isLoading = false
        }
    }
    
    var view: some View {
        container
    }
    
    var content: some View {
        VStack {
            fields
            if tx.isFastVault {
                fastVaultButton
            }
            button
        }
        .blur(radius: depositVerifyViewModel.isLoading ? 1 : 0)
    }
    
    var fastVaultButton: some View {
        Button {
            fastPasswordPresented = true
        } label: {
            FilledButton(title: NSLocalizedString("fastSign", comment: ""))
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $tx.fastVaultPassword,
                vault: vault,
                onSubmit: {
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        Task {
                            
                            keysignPayload = await depositVerifyViewModel.createKeysignPayload(tx: tx, vault: vault)
                            
                            if keysignPayload != nil {
                                depositViewModel.moveToNextView()
                            }
                            
                        }
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
        ScrollView {
            VStack(spacing: 30) {
                summary
                //checkboxes
            }
            .padding(.horizontal, 16)
        }
    }
    
    var summary: some View {
        VStack(spacing: 16) {
            getAddressCell(for: "from", with: tx.fromAddress)
            
            if tx.amountDecimal > 0 {
                Separator()
                getDetailsCell(for: "amount", with: getAmount())
            }
            
            VStack {
                ForEach(Array(tx.memoFunctionDictionary.allKeysInOrder()), id: \.self) { key in
                    if let value = tx.memoFunctionDictionary.get(key) {
                        if !value.isEmpty && value != "0" && value != "0.0" {
                            Separator()
                            getAddressCell(for: key.toFormattedTitleCase(), with: value)
                        }
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
                Task {
                    
                    keysignPayload = await depositVerifyViewModel.createKeysignPayload(tx: tx, vault: vault)
                    
                    if keysignPayload != nil {
                        depositViewModel.moveToNextView()
                    }
                    
                }
            }
            
        } label: {
            FilledButton(title: "sign")
        }
        .padding(40)
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
        tx.amount + " " + tx.coin.ticker
    }
}

#Preview {
    TransactionMemoVerifyView(
        keysignPayload: .constant(nil),
        depositViewModel: TransactionMemoViewModel(),
        depositVerifyViewModel: TransactionMemoVerifyViewModel(),
        tx: SendTransaction(),
        vault: Vault.example
    )
}
