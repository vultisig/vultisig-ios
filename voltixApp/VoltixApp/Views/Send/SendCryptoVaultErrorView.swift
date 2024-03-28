//
//  SendCryptoVaultErrorView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-20.
//

import SwiftUI

struct SendCryptoVaultErrorView: View {
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
        Button {
            dismiss()
        } label: {
            FilledButton(title: "changeVault")
        }
        .padding(40)
    }
}

#Preview {
    ZStack {
        Background()
        SendCryptoVaultErrorView()
    }
}
