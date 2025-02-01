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
    
    @State var isLinkActive = false
    
    var body: some View {
        container
            .navigationDestination(isPresented: $isLinkActive) {
                HomeView(selectedVault: vault, showVaultsList: false, shouldJoinKeygen: false)
            }
    }
    
    var main: some View {
        ZStack {
            Background()
            content
        }
    }
    
    var content: some View {
        VStack {
            animation
            text
            button
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
    
    var button: some View {
        nextButton
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
    }
    
    var nextButton: some View {
        Button {
            nextTapped()
        } label: {
            FilledButton(icon: "chevron.right")
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
        .frame(width: 80)
        .padding(.bottom, 50)
    }
    
    private func nextTapped() {
        isLinkActive = true
    }
}

#Preview {
    BackupVaultSuccessView(vault: Vault.example)
}
