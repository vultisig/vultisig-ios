//
//  TronFreezeView+iOS.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

#if os(iOS)
extension TronFreezeView {
    var main: some View {
        ZStack {
            VaultMainScreenBackground()
            content
        }
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
