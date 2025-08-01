//
//  SendCryptoStartErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-20.
//

import SwiftUI

struct SendCryptoStartErrorView: View {
    @Environment(\.theme) var theme
    let errorText: String
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            errorMessage
            Spacer()
            bottomBar
        }
    }
    
    var errorMessage: some View {
        ErrorMessage(text: "failToStartKesign")
    }
    
    var bottomBar: some View {
        VStack {
            sameWifiInstruction
            tryAgainButton
        }
    }
    
    var sameWifiInstruction: some View {
        Text(errorText)
            .font(theme.fonts.caption12)
            .foregroundColor(.neutral0)
            .padding(.horizontal, 50)
            .multilineTextAlignment(.center)
    }
    
    var tryAgainButton: some View {
        PrimaryNavigationButton(title: "tryAgain") {
            HomeView()
        }
        .padding(40)
    }
}

#Preview {
    SendCryptoStartErrorView(errorText: "error")
}
