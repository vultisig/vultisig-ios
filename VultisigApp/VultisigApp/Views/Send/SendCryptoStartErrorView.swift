//
//  SendCryptoStartErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-20.
//

import SwiftUI

struct SendCryptoStartErrorView: View {
    let errorText: String
    @State private var navigateToHome: Bool = false

    var body: some View {
        ErrorView(
            type: .warning,
            title: "failToStartKesign".localized,
            description: errorText,
            buttonTitle: "tryAgain".localized
        ) {
            navigateToHome = true
        }.navigationDestination(isPresented: $navigateToHome) {
            HomeScreen()
        }
    }
}

#Preview {
    SendCryptoStartErrorView(errorText: "error")
}
