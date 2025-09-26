//
//  KeysignSameDeviceShareErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-18.
//

import SwiftUI

struct KeysignSameDeviceShareErrorView: View {
    @State private var navigateToHome: Bool = false

    var body: some View {
        ErrorView(
            type: .warning,
            title: "sameDeviceShareError".localized,
            description: "",
            buttonTitle: "goToHomeView".localized
        ) {
            navigateToHome = true
        }.navigationDestination(isPresented: $navigateToHome) {
            HomeScreen(showingVaultSelector: true)
        }
    }
}

#Preview {
    ZStack {
        Background()
        KeysignSameDeviceShareErrorView()
    }
}
