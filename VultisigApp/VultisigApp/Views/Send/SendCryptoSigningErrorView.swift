//
//  SendCryptoErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-20.
//

import SwiftUI

struct SendCryptoSigningErrorView: View {
    let errorString: String
    
    @State private var navigateToHome: Bool = false
    
    var body: some View {
        ErrorView(
            type: .alert,
            title: "transactionFailed".localized,
            description: errorString,
            buttonTitle: "tryAgain".localized
        ) {
            navigateToHome = true
        }.navigationDestination(isPresented: $navigateToHome) {
            HomeView()
        }
    }
}

#Preview {
    ZStack {
        Background()
        SendCryptoSigningErrorView(errorString: "Error Message")
    }
}
