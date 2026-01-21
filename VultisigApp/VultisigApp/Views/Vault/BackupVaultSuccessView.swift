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

    @State var activeSummary: OnboardingSummaryView.Kind? = nil
    
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        container
            .crossPlatformSheet(item: $activeSummary) { activeSummary in
                OnboardingSummaryView(
                    kind: activeSummary,
                    isPresented: Binding(
                        get: { true },
                        set: { self.activeSummary = $0 ? activeSummary : nil }
                    ),
                    onDismiss: { goToHome() },
                    vault: vault
                )
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
            } else {
                Spacer()
            }
        }
    }
    
    var migrateText: some View {
        VStack(spacing: 2) {
            Text(NSLocalizedString("vaultUpgraded", comment: ""))
                .foregroundColor(Theme.colors.textPrimary)
            
            Text(NSLocalizedString("successfully", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient)
        }
        .font(Theme.fonts.largeTitle)
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
        .multilineTextAlignment(.center)
    }
    
    var text: some View {
        VStack(spacing: 2) {
            Text(NSLocalizedString("wellDone.", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient)
            
            Text(NSLocalizedString("readyToUseNewWalletStandard.", comment: ""))
                .foregroundColor(Theme.colors.textPrimary)
        }
        .font(Theme.fonts.largeTitle)
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }
    
    var migrateButton: some View {
        PrimaryButton(title: "goToWallet") {
            goToHome()
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
        IconButton(icon: "chevron-right") {
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
        switch vault.libType {
        case .GG20, .DKLS, .none:
            activeSummary = vault.isFastVault ? .fast : .secure
        case .KeyImport:
            activeSummary = .keyImport
        }
    }
    
    func goToHome() {
        appViewModel.set(selectedVault: vault)
    }
}

#Preview {
    BackupVaultSuccessView(tssType: .Keygen, vault: Vault.example)
}
