//
//  CircleWithdrawView+iOS.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-13.
//

import SwiftUI

#if os(iOS)
extension CircleWithdrawView {
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
        .navigationDestination(item: $keysignPayload) { payload in
            SendRouteBuilder().buildPairScreen(
                vault: vault,
                tx: sendTransaction,
                keysignPayload: payload,
                fastVaultPassword: fastVaultPassword.nilIfEmpty
            )
        }
        .crossPlatformSheet(isPresented: $fastPasswordPresented) {
            FastVaultEnterPasswordView(
                password: $fastVaultPassword,
                vault: vault,
                onSubmit: { Task { await handleWithdraw() } }
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
