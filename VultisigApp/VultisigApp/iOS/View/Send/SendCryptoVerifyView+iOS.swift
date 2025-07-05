//
//  SendCryptoVerifyView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-10.
//

#if os(iOS)
import SwiftUI

extension SendCryptoVerifyView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var container: some View {
        content
    }
    
    var pairedSignButton: some View {
        VStack {
            if sendCryptoVerifyViewModel.isValidForm {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(.extraLightGray)
                    .font(.body14BrockmannMedium)
            }
            
            ZStack {
                if tx.isFastVault {
                    OutlineButton(
                        title: "Paired sign",
                        textColor: sendCryptoVerifyViewModel.isValidForm ? .primaryGradient : .solidGray,
                        gradient: sendCryptoVerifyViewModel.isValidForm ? .primaryGradient : .solidGray
                    )
                } else {
                    FilledButton(
                        title: NSLocalizedString("signTransaction", comment: ""),
                        textColor: sendCryptoVerifyViewModel.isValidForm ? .neutral0 : .textDisabled,
                        background: sendCryptoVerifyViewModel.isValidForm ? Color.persianBlue400 : .buttonDisabled
                    )
                }
            }
            .disabled(!sendCryptoVerifyViewModel.isValidForm)
            .padding(.horizontal, 16)
            .padding(.bottom, idiom == .pad ? 30 : 0)
            .onLongPressGesture {
                signPressed()
            }
        }
    }
    
    var fastVaultButton: some View {
        Button {
            fastPasswordPresented = true
        } label: {
            FilledButton(title: NSLocalizedString("fastSign", comment: ""))
        }
        .disabled(!sendCryptoVerifyViewModel.isValidForm)
        .opacity(!sendCryptoVerifyViewModel.isValidForm ? 0.5 : 1)
        .padding(.horizontal, 16)
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
