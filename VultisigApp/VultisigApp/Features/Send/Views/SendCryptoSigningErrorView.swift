//
//  SendCryptoErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-20.
//

import SwiftUI

struct SendCryptoSigningErrorView: View {
    let errorString: String

    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        ErrorView(
            type: .alert,
            title: "transactionFailed".localized,
            description: errorString,
            buttonTitle: "tryAgain".localized
        ) {
            appViewModel.restart()
        }
    }
}

#Preview {
    ZStack {
        Background()
        SendCryptoSigningErrorView(errorString: "Error Message")
    }
    .environmentObject(AppViewModel())
}
