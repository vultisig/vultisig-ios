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
    
    @State var secureAnimationVM: RiveViewModel? = nil
    @State var fastAnimationVM: RiveViewModel? = nil
    
    @State var isLinkActive = false
    
    var body: some View {
        container
            .navigationDestination(isPresented: $isLinkActive) {
                VaultSetupSummaryView(vault: vault)
            }
            .onAppear {
                setData()
            }
            .onDisappear {
                secureAnimationVM?.stop()
                fastAnimationVM?.stop()
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
            if let fastAnimationVM {
                fastAnimationVM.view()
            } else if let secureAnimationVM {
                secureAnimationVM.view()
            } else {
                Spacer()
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
    
    private func setData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if vault.isFastVault {
                fastAnimationVM = RiveViewModel(fileName: "FastVaultBackupSucces", autoPlay: true)
            } else {
                secureAnimationVM = RiveViewModel(fileName: "SecureVaultBackupSuccess", autoPlay: true)
            }
        }
    }
    
    private func nextTapped() {
        isLinkActive = true
    }
}

#Preview {
    BackupVaultSuccessView(vault: Vault.example)
}
