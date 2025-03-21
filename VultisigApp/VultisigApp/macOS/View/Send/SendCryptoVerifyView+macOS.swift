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
        Button {
            signPressed()
        } label: {
            if tx.isFastVault {
                OutlineButton(title: "Paired sign")
            } else {
                FilledButton(title: "sign")
            }
        }
        .disabled(!sendCryptoVerifyViewModel.isValidForm)
        .opacity(!sendCryptoVerifyViewModel.isValidForm ? 0.5 : 1)
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
