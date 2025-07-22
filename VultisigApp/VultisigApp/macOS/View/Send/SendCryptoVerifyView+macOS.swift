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
                
                PrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {}
                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                        signPressed()
                    })
                    .simultaneousGesture(TapGesture().onEnded { _ in
                        fastPasswordPresented = true
                    })
                    .sheet(isPresented: $fastPasswordPresented) {
                        FastVaultEnterPasswordView(
                            password: $tx.fastVaultPassword,
                            vault: vault,
                            onSubmit: { signPressed() }
                        )
                    }
            } else {
                PrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {
                    signPressed()
                }
            }
        }
        .disabled(!sendCryptoVerifyViewModel.isValidForm)
        .padding(.horizontal, 40)
    }
}
#endif
