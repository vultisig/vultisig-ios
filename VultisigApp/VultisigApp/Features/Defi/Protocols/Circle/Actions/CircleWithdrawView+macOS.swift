//
//  CircleWithdrawView+macOS.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-13.
//

import SwiftUI

#if os(macOS)
extension CircleWithdrawView {
    var main: some View {
        content
            .background(Theme.colors.bgPrimary)
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
        scrollableContent
    }
}
#endif
