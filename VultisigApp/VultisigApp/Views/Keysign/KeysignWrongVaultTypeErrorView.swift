//
//  KeysignWrongVaultTypeErrorView.swift
//  VultisigApp
//
//  Created by Johnny Luo on 30/4/2025.
//

import SwiftUI

struct KeysignWrongVaultTypeErrorView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    
    var body: some View {
        ErrorView(
            type: .warning,
            title: "vaultTypeDoesnotMatch".localized,
            description: "",
            buttonTitle: "tryAgain".localized
        ) {
            appViewModel.set(selectedVault: appViewModel.selectedVault, showingVaultSelector: true)
        }
    }
}

#Preview {
    ZStack {
        Background()
        KeysignWrongVaultTypeErrorView()
            .environmentObject(AppViewModel())
    }
}
