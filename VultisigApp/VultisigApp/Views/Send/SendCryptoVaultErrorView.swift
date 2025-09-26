//
//  SendCryptoVaultErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-20.
//

import SwiftUI

struct SendCryptoVaultErrorView: View {
    @State private var navigateToHome: Bool = false

    var body: some View {
        ErrorView(
            type: .warning,
            title: "wrongVaultTryAgain".localized,
            description: "",
            buttonTitle: "changeVault".localized
        ) {
            navigateToHome = true
        }.navigationDestination(isPresented: $navigateToHome) {
            HomeScreen(showingVaultSelector: true)
        }
    }
}

#Preview {
    SendCryptoVaultErrorView()
}
