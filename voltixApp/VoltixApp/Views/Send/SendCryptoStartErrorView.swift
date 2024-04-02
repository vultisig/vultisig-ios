//
//  SendCryptoStartErrorView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-20.
//

import SwiftUI

struct SendCryptoStartErrorView: View {
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
        ErrorMessage(text: "failToStart")
    }
    
    var bottomBar: some View {
        VStack {
            sameWifiInstruction
            tryAgainButton
        }
    }
    
    var sameWifiInstruction: some View {
        Text(errorText)
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .padding(.horizontal, 50)
            .multilineTextAlignment(.center)
    }
    
    var tryAgainButton: some View {
        NavigationLink {
            HomeView()
        } label: {
            FilledButton(title: "tryAgain")
        }
        .padding(40)
    }
}

#Preview {
    SendCryptoStartErrorView(errorText: "error")
}
