//
//  SendCryptoVaultErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-20.
//

import SwiftUI

struct SendCryptoVaultErrorView: View {
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        ErrorView(
            type: .warning,
            title: "wrongVaultTryAgain".localized,
            description: "",
            buttonTitle: "changeVault".localized
        ) {
            appViewModel.set(selectedVault: appViewModel.selectedVault, showingVaultSelector: true)
        }
    }
}

#Preview {
    SendCryptoVaultErrorView()
        .environmentObject(AppViewModel())
}
