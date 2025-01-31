//
//  BackupVaultSuccessView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-31.
//

import SwiftUI
import RiveRuntime

struct BackupVaultSuccessView: View {
    let vault: Vault
    
    let secureAnimationVM = RiveViewModel(fileName: "SecureVaultBackupSuccess", autoPlay: true)
    let fastAnimationVM = RiveViewModel(fileName: "FastVaultBackupSucces", autoPlay: true)
    
    let loaderAnimationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
    
    var body: some View {
        ZStack {
            Background()
            content
        }
    }
    
    var content: some View {
        VStack {
            Spacer()
            animation
            Spacer()
            text
            loader
        }
    }
    
    var animation: some View {
        ZStack {
            if vault.isFastVault {
                fastAnimationVM.view()
            } else {
                secureAnimationVM.view()
            }
        }
    }
    
    var text: some View {
        VStack(spacing: 2) {
            Text(NSLocalizedString("wellDone.", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient)
            
            Text(NSLocalizedString("readyToUseNewWalletStandard.", comment: ""))
                .foregroundColor(.neutral0)
        }
        .font(.body34BrockmannMedium)
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }
    
    var loader: some View {
        loaderAnimationVM.view()
            .frame(width: 24, height: 24)
            .padding(.bottom, 100)
    }
}

#Preview {
    BackupVaultSuccessView(vault: Vault.example)
}
