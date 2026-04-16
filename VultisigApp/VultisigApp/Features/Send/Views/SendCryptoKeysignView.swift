//
//  SendCryptoKeysignView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-17.
//

import SwiftUI

struct SendCryptoKeysignView: View {
    var title: String? = nil
    var showError = false
    var coinLogo: String? = nil

    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        ZStack {
            if showError {
                errorView
            } else {
                KeysignAnimationView(connected: .constant(true), coinLogo: coinLogo)
            }
        }
    }

    var errorView: some View {
        ErrorView(
            type: .warning,
            title: "signingErrorTryAgain".localized,
            description: title?.localized ?? .empty,
            buttonTitle: "tryAgain".localized
        ) {
            appViewModel.restart()
        }
    }
}

#Preview {
    ZStack {
        Theme.colors.bgPrimary
            .ignoresSafeArea()

        SendCryptoKeysignView()
    }
    .environmentObject(AppViewModel())
}
