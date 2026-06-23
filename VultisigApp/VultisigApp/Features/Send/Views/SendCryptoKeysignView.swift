//
//  SendCryptoKeysignView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-17.
//

import SwiftUI
import RiveRuntime

struct SendCryptoKeysignView: View {
    var title: String? = nil
    var showError = false
    var coinLogo: String? = nil
    var progress: Float = 0
    var errorButtonTitle: String? = nil
    var errorAction: (() -> Void)? = nil

    @State var loadingAnimationVM: RiveViewModel? = nil

    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        ZStack {
            if showError {
                errorView
            } else {
                KeysignAnimationView(connected: .constant(true), coinLogo: coinLogo, progress: progress)
            }
        }
    }

    var errorView: some View {
        ErrorView(
            type: .warning,
            title: "signingErrorTryAgain".localized,
            description: title?.localized ?? .empty,
            buttonTitle: errorButtonTitle ?? "tryAgain".localized
        ) {
            if let errorAction {
                errorAction()
            } else {
                appViewModel.restart()
            }
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
