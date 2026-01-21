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
            .background(VaultMainScreenBackground())
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
