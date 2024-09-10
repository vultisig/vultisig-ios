//
//  SendCryptoErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-20.
//

import SwiftUI

struct SendCryptoSigningErrorView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        container
    }
    
    var content: some View {
        VStack(spacing: 22) {
            Spacer()
            errorMessage
            Spacer()
            bottomBar
        }
    }
    
    var errorMessage: some View {
        ErrorMessage(text: "signInErrorTryAgain")
    }
    
    var bottomBar: some View {
        VStack {
            sameWifiInstruction
            tryAgainButton
        }
    }
    
    var sameWifiInstruction: some View {
        InformationNote()
            .padding(.horizontal, 16)
    }
    
    var tryAgainButton: some View {
        NavigationLink {
            HomeView()
        } label: {
            FilledButton(title: "tryAgain")
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 15)
        .id(UUID())
    }
}

#Preview {
    ZStack {
        Background()
        SendCryptoSigningErrorView()
    }
}
