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
    
    @Environment(\.dismiss) var dismiss
    
    @State var loadingAnimationVM: RiveViewModel? = nil
    
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    
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
        VStack(spacing: 22) {
            Spacer()
            errorMessage
            Spacer()
            bottomBar
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
    
    var errorMessage: some View {
        VStack(spacing: 32) {
            ErrorMessage(text: "signInErrorTryAgain")
            if let title {
                Text(NSLocalizedString(title, comment: ""))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundColor(Theme.colors.textPrimary)
            }
        }
    }
    
    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(Theme.colors.alertInfo)
            .opacity(0.05)
            .blur(radius: 20)
    }
    
    var bottomBar: some View {
        VStack {
            InformationNote()
                .padding(.horizontal, 16)
            tryAgainButton
        }
    }
    
    var tryAgainButton: some View {
        PrimaryNavigationButton(title: "tryAgain") {
            HomeView()
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 15)
    }
    
    var appVersion: some View {
        Text("Version \(version ?? "1").\(build ?? "1")")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textExtraLight)
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
}
