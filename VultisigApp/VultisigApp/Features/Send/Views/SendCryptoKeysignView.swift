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
    /// Drives the Rive `Connected` boolean on the signing animation. `false`
    /// renders the "connecting/searching" visual while the relay session is
    /// still bootstrapping (fast-vault flow); `true` is the signing visual.
    var connected: Bool = true
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
                KeysignAnimationView(connected: .constant(connected), coinLogo: coinLogo, progress: progress)
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
