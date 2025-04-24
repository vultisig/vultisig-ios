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
        .onAppear {
            setData()
        }
    }
    
    var signingView: some View {
        VStack {
            disclaimer
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
                    .font(.body16MenloBold)
                    .foregroundColor(.neutral0)
            } else {
                Text(NSLocalizedString("signingTransaction", comment: ""))
                    .font(.body16MenloBold)
                    .foregroundColor(.neutral0)
            }
        }
    }
    
    var animation: some View {
        loadingAnimationVM?.view()
            .frame(width: 28, height: 28)
    }
    
    var errorMessage: some View {
        ErrorMessage(text: "signInErrorTryAgain")
    }
    
    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(.alertTurquoise)
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
        NavigationLink {
            HomeView()
        } label: {
            FilledButton(title: "tryAgain")
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 15)
    }
    
    var appVersion: some View {
        Text("Version \(version ?? "1").\(build ?? "1")")
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
            .padding(.bottom, 30)
    }
    
    var disclaimer: some View {
        HStack(spacing: 12) {
            infoIcon
            text
        }
        .foregroundColor(.neutral0)
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue200, lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }
    
    var infoIcon: some View {
        Image(systemName: "info.circle")
            .resizable()
            .frame(width: 12, height: 12)
    }
    
    var text: some View {
        Text(NSLocalizedString("sendCryptoKeysignViewDisclaimer", comment: ""))
            .font(.body12BrockmannMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func setData() {
        loadingAnimationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
    }
}

#Preview {
    ZStack {
        Color.blue800
            .ignoresSafeArea()
        
        SendCryptoKeysignView()
    }
}
