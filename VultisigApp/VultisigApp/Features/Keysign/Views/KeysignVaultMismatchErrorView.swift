//
//  KeysignVaultMismatchErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-26.
//

import SwiftUI

struct KeysignVaultMismatchErrorView: View {
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        ErrorView(
            type: .warning,
            title: "wrongVaultTryAgain".localized,
            description: "",
            buttonTitle: "tryAgain".localized
        ) {
            appViewModel.set(selectedVault: appViewModel.selectedVault, showingVaultSelector: true)
        }
    }
}

#Preview {
    KeysignVaultMismatchErrorView()
        .environmentObject(AppViewModel())
}
