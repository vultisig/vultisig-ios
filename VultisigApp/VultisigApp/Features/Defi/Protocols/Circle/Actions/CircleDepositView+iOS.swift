//
//  CircleDepositView+iOS.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-13.
//

import SwiftUI

#if os(iOS)
extension CircleDepositView {
    var main: some View {
        ZStack {
            Theme.colors.bgPrimary.ignoresSafeArea()
            content
        }
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
