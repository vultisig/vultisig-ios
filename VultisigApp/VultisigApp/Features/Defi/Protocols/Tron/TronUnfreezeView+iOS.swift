//
//  TronUnfreezeView+iOS.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

#if os(iOS)
extension TronUnfreezeView {
    var main: some View {
        ZStack {
            VaultMainScreenBackground()
            content
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            Task {
                await loadFastVaultStatus()
            }
        }
        .crossPlatformSheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $fastVaultPassword,
                vault: vault,
                onSubmit: { Task { await handleUnfreeze() } }
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
