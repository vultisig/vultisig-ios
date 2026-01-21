//
//  SecureBackupVaultOverview.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-31.
//

import SwiftUI
import RiveRuntime

struct SecureBackupVaultOverview: View {
    let vault: Vault
    
    @State var tabIndex = 0
    @State var isVerificationLinkActive = false
    @State var animationVM: RiveViewModel? = nil
    @Environment(\.router) var router

    let totalTabCount = 2

    var body: some View {
        ZStack {
            Background()
            animation
            container
        }
        .onAppear {
            animationVM = RiveViewModel(fileName: "securevault_overview", autoPlay: true)
        }
        .onDisappear {
            animationVM?.stop()
        }
    }
    
    var content: some View {
        VStack(spacing: 0) {
            header
            progressBar
            Spacer()
            textTabView
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
        Text(NSLocalizedString("vaultOverview", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyLMedium)
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
        .frame(width: 80)
    }
    
    private func nextTapped() {        
        guard tabIndex<totalTabCount-1 else {
            moveToBackupView()
            return
        }
        
        tabIndex+=1
    }
    
    private func moveToBackupView() {
        router.navigate(to: KeygenRoute.backupNow(
            tssType: .Keygen,
            backupType: .single(vault: vault),
            isNewVault: true
        ))
    }
    
    private func animate(index: Int) {
        animationVM?.setInput("Index", value: Double(index))
    }
}

#Preview {
    SecureBackupVaultOverview(vault: Vault.example)
}
