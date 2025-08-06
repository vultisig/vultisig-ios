//
//  BackupVaultSuccessView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-31.
//

import SwiftUI
import RiveRuntime

struct BackupVaultSuccessView: View {
    let tssType: TssType
    let vault: Vault
    
    @State var secureAnimationVM: RiveViewModel? = nil
    @State var fastAnimationVM: RiveViewModel? = nil
    @State var upgradeAnimationVM: RiveViewModel? = nil

    @State var isHomeViewActive = false
    @State var isFastSummaryActive = false
    @State var isSecureSummaryActive = false

    var body: some View {
        container
            .navigationDestination(isPresented: $isHomeViewActive) {
                HomeView(selectedVault: vault, showVaultsList: false, shouldJoinKeygen: false)
            }
            .sheet(isPresented: $isFastSummaryActive) {
                OnboardingSummaryView(kind: .fast, isPresented: $isFastSummaryActive, onDismiss: {
                    isHomeViewActive = true
                }, vault: vault)
            }
            .sheet(isPresented: $isSecureSummaryActive) {
                OnboardingSummaryView(kind: .secure, isPresented: $isSecureSummaryActive, onDismiss: {
                    isHomeViewActive = true
                }, vault: vault)
            }
            .onAppear {
                setData()
            }
            .onDisappear {
                secureAnimationVM?.stop()
                fastAnimationVM?.stop()
                upgradeAnimationVM?.stop()
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
            
            if tssType == .Migrate {
                migrateText
                migrateButton
            } else {
                text
                button
            }
        }
    }
    
    var animation: some View {
        ZStack {
            if let fastAnimationVM {
                fastAnimationVM.view()
            } else if let secureAnimationVM {
                secureAnimationVM.view()
            } else if let upgradeAnimationVM {
                upgradeAnimationVM.view()
            }
            else {
                Spacer()
            }
        }
    }
    
    var migrateText: some View {
        VStack(spacing: 2) {
            Text(NSLocalizedString("vaultUpgraded", comment: ""))
                .foregroundColor(.neutral0)
            
            Text(NSLocalizedString("successfully", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient)
        }
        .font(.body34BrockmannMedium)
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
        .multilineTextAlignment(.center)
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
    
    var migrateButton: some View {
        PrimaryButton(title: "goToWallet") {
            isHomeViewActive = true
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 40)
    }
    
    var button: some View {
        nextButton
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
    }
    
    var nextButton: some View {
        IconButton(icon: "chevron.right") {
            nextTapped()
        }
        .frame(width: 80)
        .padding(.bottom, 50)
    }
    
    private func setData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if tssType == .Migrate {
                    upgradeAnimationVM = RiveViewModel(fileName: "upgrade_success", autoPlay: true)
            } else {
                if vault.isFastVault {
                    fastAnimationVM = RiveViewModel(fileName: "FastVaultBackupSucces", autoPlay: true)
                } else {
                    secureAnimationVM = RiveViewModel(fileName: "SecureVaultBackupSuccess", autoPlay: true)
                }
            }
        }
    }
    
    private func nextTapped() {
        if vault.isFastVault {
            isFastSummaryActive = true
        } else {
            isSecureSummaryActive = true
        }
    }
}

#Preview {
    BackupVaultSuccessView(tssType: .Keygen, vault: Vault.example)
}
