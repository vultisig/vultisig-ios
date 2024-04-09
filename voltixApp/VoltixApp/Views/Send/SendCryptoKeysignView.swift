//
//  SendCryptoKeysignView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-17.
//

import SwiftUI

struct SendCryptoKeysignView: View {
    let vault: Vault
    let title: String
    var showError = false
    @State var didSwitch = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        if showError {
            errorView
        } else {
            signingView
        }
    }
    
    var signingView: some View {
        VStack {
            Spacer()
            signingAnimation
            Spacer()
            wifiInstructions
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
            Text(NSLocalizedString(title, comment: "Signing"))
                .font(.body16MenloBold)
                .foregroundColor(.neutral0)
            animation
        }
    }
    
    var animation: some View {
        HStack {
            Circle()
                .frame(width: 20, height: 20)
                .foregroundColor(.loadingBlue)
                .offset(x: didSwitch ? 0 : 28)
            
            Circle()
                .frame(width: 20, height: 20)
                .foregroundColor(.loadingGreen)
                .offset(x: didSwitch ? 0 : -28)
        }
        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: didSwitch)
        .onAppear {
            didSwitch.toggle()
        }
    }
    
    var wifiInstructions: some View {
        WifiInstruction()
            .frame(maxHeight: 80)
            .padding(.bottom, 100)
    }
    
    var errorMessage: some View {
        ErrorMessage(text: "signInErrorTryAgain")
    }
    
    var bottomBar: some View {
        VStack {
            sameWifiInstruction
            tryAgainButton
        }
    }
    
    var sameWifiInstruction: some View {
        Text(NSLocalizedString("sameWifiEntendedInstruction", comment: "Keep devices on the same WiFi Network, correct vault and pair devices. Make sure no other devices are running Voltix."))
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .padding(.horizontal, 50)
            .multilineTextAlignment(.center)
    }
    
    var tryAgainButton: some View {
        NavigationLink {
            HomeView(selectedVault: vault,showVaultsList: false)
        } label: {
            FilledButton(title: "tryAgain")
        }
        .padding(40)
    }
}

#Preview {
    ZStack {
        Color.blue800
            .ignoresSafeArea()
        
        SendCryptoKeysignView(vault:Vault.example,title: "signing")
    }
}
