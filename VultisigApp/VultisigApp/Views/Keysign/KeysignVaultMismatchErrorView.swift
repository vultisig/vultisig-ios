//
//  KeysignVaultMismatchErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-26.
//

import SwiftUI

struct KeysignVaultMismatchErrorView: View {
    @State private var navigateToHome: Bool = false

    var body: some View {
        ErrorView(
            type: .warning,
            title: "wrongVaultTryAgain".localized,
            description: "",
            buttonTitle: "tryAgain".localized
        ) {
            navigateToHome = true
        }.navigationDestination(isPresented: $navigateToHome) {
            HomeScreen(showingVaultSelector: true)
        }
    }
}

#Preview {
    KeysignVaultMismatchErrorView()
}
