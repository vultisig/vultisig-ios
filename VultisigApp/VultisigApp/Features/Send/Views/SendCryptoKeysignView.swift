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
    var errorButtonTitle: String? = nil
    var errorAction: (() -> Void)? = nil

    @State var loadingAnimationVM: RiveViewModel? = nil

    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        ZStack {
            shadow

            if showError {
                errorView
            } else {
                signingView
            }
        }
        .onLoad {
            setData()
        }
    }

    var signingView: some View {
        VStack {
            Spacer()
            signingAnimation
            Spacer()
            appVersion
        }
    }

    var errorView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Theme.colors.alertWarning)
                    .background(Image("CirclesBackground"))
                    .padding(.bottom, 12)
                Text("signingErrorTryAgain".localized)
                    .foregroundStyle(Theme.colors.alertWarning)
                    .font(Theme.fonts.title2)
                    .multilineTextAlignment(.center)
                if let title, title.isNotEmpty {
                    Text(title.localized)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .font(Theme.fonts.bodySMedium)
                        .multilineTextAlignment(.center)
                }
                PrimaryButton(
                    title: errorButtonTitle ?? "tryAgain".localized,
                    type: .secondary
                ) {
                    if let errorAction {
                        errorAction()
                    } else {
                        appViewModel.restart()
                    }
                }
            }
            .padding(.horizontal, 24)
            Spacer()
            appVersion
        }
    }

    var signingAnimation: some View {
        VStack(spacing: 32) {
            animation

            if let title {
                Text(NSLocalizedString(title, comment: ""))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundColor(Theme.colors.textPrimary)
            } else {
                Text(NSLocalizedString("signingTransaction", comment: ""))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundColor(Theme.colors.textPrimary)
            }
        }
    }

    var animation: some View {
        loadingAnimationVM?.view()
            .frame(width: 28, height: 28)
    }

    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(Theme.colors.alertInfo)
            .opacity(0.05)
            .blur(radius: 20)
    }

    var appVersion: some View {
        Text(Bundle.main.appVersionString)
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textTertiary)
            .padding(.bottom, 30)
    }

    private func setData() {
        loadingAnimationVM = RiveViewModel(fileName: "connecting_with_server", autoPlay: true)
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
