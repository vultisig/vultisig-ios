//
//  SendCryptoVerifyView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-10.
//

#if os(macOS)
import SwiftUI

extension SendCryptoVerifyView {
    var container: some View {
        content
            .padding(26)
    }
    
    var pairedSignButton: some View {
        VStack {
            if tx.isFastVault {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(.extraLightGray)
                    .font(.body14BrockmannMedium)
                
                OutlineButton(
                    title: "Paired sign",
                    textColor: sendCryptoVerifyViewModel.isValidForm ? .primaryGradient : .solidGray,
                    gradient: sendCryptoVerifyViewModel.isValidForm ? .primaryGradient : .solidGray
                )
                .onLongPressGesture {
                    signPressed()
                }
            } else {
                FilledButton(
                    title: NSLocalizedString("signTransaction", comment: ""),
                    textColor: sendCryptoVerifyViewModel.isValidForm ? .neutral0 : .textDisabled,
                    background: sendCryptoVerifyViewModel.isValidForm ? Color.persianBlue400 : .buttonDisabled
                )
                .onTapGesture {
                    signPressed()
                }
            }
        }
        .disabled(!sendCryptoVerifyViewModel.isValidForm)
        .padding(.horizontal, 40)
    }
    
    var fastVaultButton: some View {
        Button {
            fastPasswordPresented = true
        } label: {
            FilledButton(title: NSLocalizedString("fastSign", comment: ""))
        }
        .disabled(!sendCryptoVerifyViewModel.isValidForm)
        .opacity(!sendCryptoVerifyViewModel.isValidForm ? 0.5 : 1)
        .padding(.horizontal, 40)
        .sheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $tx.fastVaultPassword,
                vault: vault,
                onSubmit: { signPressed() }
            )
        }
    }
}
#endif
