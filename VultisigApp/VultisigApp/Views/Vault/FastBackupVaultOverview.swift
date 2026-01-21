//
//  FastBackupVaultOverview.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-01.
//

import SwiftUI
import RiveRuntime

struct FastBackupVaultOverview: View {
    let tssType: TssType
    let vault: Vault
    let email: String
    
    let totalTabCount = 4
    
    @State var tabIndex = 0
    @State var isVerificationLinkActive = false
    
    @State var animationVM: RiveViewModel? = nil
    @State var backupVaultAnimationVM: RiveViewModel? = nil
    @Environment(\.router) var router

    var body: some View {
        ZStack {
            Background()
            animation
            container
        }
        .crossPlatformSheet(isPresented: $isVerificationLinkActive) {
            ServerBackupVerificationView(
                tssType: tssType,
                vault: vault,
                email: email,
                isPresented: $isVerificationLinkActive,
                tabIndex: $tabIndex,
                onBackup: {
                    onBackup()
                }, onBackToEmailSetup: {
                    router.navigate(to: KeygenRoute.newWalletName(
                        tssType: .Keygen,
                        selectedTab: .fast,
                        name: ""
                    ))
                }
            )
        }
        .onAppear {
            setData()
        }
    }
    
    var content: some View {
        VStack(spacing: 0) {
            if tssType == .Migrate {
                Spacer()
                migrateText
            } else {
                header
                progressBar
                Spacer()
                textTabView
            }
            
            button
        }
        .onChange(of: tabIndex) { _, newValue in
            animate(index: newValue)
        }
    }
    
    var header: some View {
        HStack {
            headerTitle
            Spacer()
        }
        .padding(16)
    }
    
    var headerTitle: some View {
        Text(NSLocalizedString(getTitle(), comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyLMedium)
    }
    
    var migrateText: some View {
        VStack(spacing: 2) {
            Text(NSLocalizedString("FastMigrateOverviewText1", comment: ""))
                .foregroundColor(Theme.colors.textPrimary)
            Text(NSLocalizedString("FastMigrateOverviewText2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient)
        }
        .font(Theme.fonts.title1)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 36)
        .padding(.bottom, 24)
    }
    
    var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(0..<totalTabCount, id: \.self) { index in
                Rectangle()
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(index <= tabIndex ? Theme.colors.bgButtonPrimary : Theme.colors.bgSurface2)
                    .animation(.easeInOut, value: tabIndex)
            }
        }
        .padding(.horizontal, 16)
    }
    
    var nextButton: some View {
        IconButton(icon: "chevron-right") {
            nextTapped()
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
        .frame(width: 80)
    }
    
    private func setData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            animationVM = RiveViewModel(fileName: "fastvault_overview", autoPlay: true)
            backupVaultAnimationVM = RiveViewModel(fileName: "backup_vault", autoPlay: true)
        }
    }
    
    private func nextTapped() {
        guard tssType != .Migrate else {
            isVerificationLinkActive = true
            return
        }
        
        if tabIndex == 2 {
            isVerificationLinkActive = true
            return
        }
        
        if tabIndex == 3 {
            onBackup()
            return
        }
        
        tabIndex += 1
    }
    
    func onBackup() {
        router.navigate(to: KeygenRoute.backupNow(
            tssType: tssType,
            backupType: .single(vault: vault),
            isNewVault: true
        ))
    }
    
    private func animate(index: Int) {
        animationVM?.setInput("Index", value: Double(index))
    }
    
    private func getTitle() -> String {
        switch tabIndex {
        case 2:
            "backupPart1"
        case 3:
            "backupPart2"
        default:
            "vaultOverview"
        }
    }
}

#Preview {
    FastBackupVaultOverview(
        tssType: .Keygen,
        vault: Vault.example,
        email: "mail@email.com"
    )
}
