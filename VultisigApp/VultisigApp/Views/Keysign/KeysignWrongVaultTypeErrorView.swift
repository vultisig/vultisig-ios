//
//  KeysignWrongVaultTypeErrorView.swift
//  VultisigApp
//
//  Created by Johnny Luo on 30/4/2025.
//


import SwiftUI

struct KeysignWrongVaultTypeErrorView: View {
    @State private var navigateToHome: Bool = false

    var body: some View {
        ErrorView(
            type: .warning,
            title: "vaultTypeDoesnotMatch".localized,
            description: "",
            buttonTitle: "tryAgain".localized
        ) {
            navigateToHome = true
        }.navigationDestination(isPresented: $navigateToHome) {
            HomeView(showVaultsList: true)
        }
    }
}

#Preview {
    ZStack {
        Background()
        KeysignWrongVaultTypeErrorView()
    }
}
