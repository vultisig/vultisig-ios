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
            if tx.isFastVault {
                Text(NSLocalizedString("holdForPairedSign", comment: ""))
                    .foregroundColor(.extraLightGray)
                    .font(.body14BrockmannMedium)
                
                PrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {}
                    .sheet(isPresented: $fastPasswordPresented) {
                        FastVaultEnterPasswordView(
                            password: $tx.fastVaultPassword,
                            vault: vault,
                            onSubmit: { signPressed() }
                        )
                    }
                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                        signPressed()
                    })
                    .simultaneousGesture(TapGesture().onEnded { _ in
                        fastPasswordPresented = true
                    })
            } else {
                PrimaryButton(title: NSLocalizedString("signTransaction", comment: "")) {
                    signPressed()
                }
            }
        }
        .disabled(!sendCryptoVerifyViewModel.isValidForm)
        .padding(.horizontal, 16)
        .padding(.bottom, idiom == .pad ? 30 : 0)
    }
}
#endif
