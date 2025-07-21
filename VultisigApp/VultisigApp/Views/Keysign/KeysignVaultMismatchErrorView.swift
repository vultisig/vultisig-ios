//
//  KeysignVaultMismatchErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-26.
//

import SwiftUI

struct KeysignVaultMismatchErrorView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            errorMessage
            Spacer()
            tryAgainButton
        }
    }
    
    var errorMessage: some View {
        ErrorMessage(text: "wrongVaultTryAgain")
    }
    
    var tryAgainButton: some View {
        PrimaryNavigationButton(title: "changeVault") {
            HomeView(showVaultsList: true)
        }
        .padding(40)
    }
}

#Preview {
    ZStack {
        Background()
        KeysignVaultMismatchErrorView()
    }
}
