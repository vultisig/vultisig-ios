//
//  KeysignWrongVaultTypeErrorView.swift
//  VultisigApp
//
//  Created by Johnny Luo on 30/4/2025.
//


import SwiftUI

struct KeysignWrongVaultTypeErrorView: View {
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
        ErrorMessage(text: "vaultTypeDoesnotMatch")
    }
    
    var tryAgainButton: some View {
        PrimaryNavigationButton(title: "tryAgain") {
            HomeView(showVaultsList: true)
        }
        .padding(40)
    }
}

#Preview {
    ZStack {
        Background()
        KeysignWrongVaultTypeErrorView()
    }
}
