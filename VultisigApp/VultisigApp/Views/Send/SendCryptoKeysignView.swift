//
//  SendCryptoKeysignView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-17.
//

import SwiftUI
import RiveRuntime

struct SendCryptoKeysignView: View {
    let title: String
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
            Text(NSLocalizedString(title, comment: "Signing"))
                .font(.body16MenloBold)
                .foregroundColor(.neutral0)
        }
    }
    
    var animation: some View {
        loadingAnimationVM?.view()
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
    
    private func setData() {
        loadingAnimationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
    }
}

#Preview {
    ZStack {
        Color.blue800
            .ignoresSafeArea()
        
        SendCryptoKeysignView(title: "signing")
    }
}
