//
//  SendCryptoErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-20.
//

import SwiftUI

struct SendCryptoSigningErrorView: View {
    let errorString: String
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            backgroundImage
            container
        }
    }
    
    var content: some View {
        VStack(spacing: 32) {
            main.opacity(0)
            errorIcon
            main
        }
    }
    
    var main: some View {
        VStack(spacing: 22) {
            errorMessage
            tryAgainButton
        }
    }
    
    var errorIcon: some View {
        Image(systemName: "xmark.circle.fill")
            .font(.body24MontserratBold)
            .foregroundColor(.alertRed)
    }
    
    var backgroundImage: some View {
        Image("CirclesBackground")
    }
    
    var errorMessage: some View {
        VStack(spacing: 18) {
            Text(NSLocalizedString("transactionFailed", comment: ""))
                .font(.body22BrockmannMedium)
                .foregroundColor(.alertRed)
            
            Text(errorString)
                .font(.body14MenloBold)
                .foregroundColor(.extraLightGray)
        }
    }
    
    var tryAgainButton: some View {
        PrimaryNavigationButton(title: "tryAgain", type: .secondary) {
            HomeView()
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 15)
        .id(UUID())
    }
}

#Preview {
    ZStack {
        Background()
        SendCryptoSigningErrorView(errorString: "Error Message")
    }
}
