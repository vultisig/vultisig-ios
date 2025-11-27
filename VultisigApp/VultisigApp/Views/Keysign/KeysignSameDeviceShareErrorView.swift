//
//  KeysignSameDeviceShareErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-18.
//

import SwiftUI

struct KeysignSameDeviceShareErrorView: View {
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        ErrorView(
            type: .warning,
            title: "sameDeviceShareError".localized,
            description: "",
            buttonTitle: "goToHomeView".localized
        ) {
            appViewModel.set(selectedVault: nil, showingVaultSelector: true)
        }
    }
}

#Preview {
    ZStack {
        Background()
        KeysignSameDeviceShareErrorView()
    }
    .environmentObject(AppViewModel())
}
