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
                
                FilledButton(
                    title: NSLocalizedString("signTransaction", comment: ""),
                    textColor: sendCryptoVerifyViewModel.isValidForm ? .neutral0 : .textDisabled,
                    background: sendCryptoVerifyViewModel.isValidForm ? Color.persianBlue400 : .buttonDisabled
                )
                .onLongPressGesture {
                    signPressed()
                }
                .onTapGesture {
                    fastPasswordPresented = true
                }
                .sheet(isPresented: $fastPasswordPresented) {
                    FastVaultEnterPasswordView(
                        password: $tx.fastVaultPassword,
                        vault: vault,
                        onSubmit: { signPressed() }
                    )
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
}
#endif
