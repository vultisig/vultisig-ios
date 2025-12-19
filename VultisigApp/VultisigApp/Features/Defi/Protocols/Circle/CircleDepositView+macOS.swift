//
//  CircleDepositView+macOS.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-13.
//

import SwiftUI

#if os(macOS)
extension CircleDepositView {
    var main: some View {
        content
             .background(VaultMainScreenBackground())
            .navigationBarBackButtonHidden(true)
            .onAppear {
                Task { await loadData() }
            }
            .navigationDestination(isPresented: $navigateToVerify) {
                SendRouteBuilder().buildVerifyScreen(tx: tx, vault: vault)
            }
    }
    
    var scrollView: some View {
        ScrollView {
            scrollableContent
        }
    }
}
#endif
