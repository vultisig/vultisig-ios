//
//  TronFreezeView+macOS.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

#if os(macOS)
extension TronFreezeView {
    var main: some View {
        content
            .background(VaultMainScreenBackground())
            .navigationBarBackButtonHidden(true)
            .onAppear {
                Task {
                    await loadData()
                    await loadFastVaultStatus()
                }
            }
            .crossPlatformSheet(isPresented: $fastPasswordPresented) {
                FastVaultEnterPasswordView(
                    password: $fastVaultPassword,
                    vault: vault,
                    onSubmit: { Task { await handleContinue() } }
                )
            }
    }
    
    var scrollView: some View {
        ScrollView {
            scrollableContent
        }
    }
}
#endif
