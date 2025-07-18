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
                
                FilledButton(
                    title: NSLocalizedString("signTransaction", comment: ""),
                    textColor: sendCryptoVerifyViewModel.isValidForm ? .neutral0 : .textDisabled,
                    background: sendCryptoVerifyViewModel.isValidForm ? Color.persianBlue400 : .buttonDisabled
                )
                .sheet(isPresented: $fastPasswordPresented) {
                    FastVaultEnterPasswordView(
                        password: $tx.fastVaultPassword,
                        vault: vault,
                        onSubmit: { signPressed() }
                    )
                }
                .onLongPressGesture {
                    signPressed()
                }
                .onTapGesture {
                    fastPasswordPresented = true
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
        .padding(.horizontal, 16)
        .padding(.bottom, idiom == .pad ? 30 : 0)
    }
}
#endif
