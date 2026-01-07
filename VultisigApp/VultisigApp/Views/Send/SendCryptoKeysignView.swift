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
        ErrorView(
            type: .warning,
            title: "signingErrorTryAgain".localized,
            description: title?.localized ?? .empty,
            buttonTitle: "tryAgain".localized
        ) {
            appViewModel.restart()
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
        loadingAnimationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
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
