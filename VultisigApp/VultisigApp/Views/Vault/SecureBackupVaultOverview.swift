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
    @State var isBackupLinkActive = false
    @State var animationVM: RiveViewModel? = nil

    let totalTabCount = 2

    var body: some View {
        ZStack {
            Background()
            animation
            container
        }
        .navigationDestination(isPresented: $isBackupLinkActive) {
            BackupSetupView(tssType: .Keygen, vault: vault, isNewVault: true)
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
        .onChange(of: tabIndex) { oldValue, newValue in
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
            .foregroundColor(.neutral0)
            .font(.body18BrockmannMedium)
    }
    
    var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(0..<totalTabCount, id: \.self) { index in
                Rectangle()
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(index <= tabIndex ? .turquoise400 : .blue400)
                    .animation(.easeInOut, value: tabIndex)
            }
        }
        .padding(.horizontal, 16)
    }
    
    var animation: some View {
        animationVM?.view()
            .offset(y: -80)
    }
    
    var text: some View {
        TabView(selection: $tabIndex) {
            ForEach(0..<totalTabCount, id: \.self) { index in
                VStack {
                    Spacer()
                    OnboardingTextCard(
                        index: index,
                        textPrefix: "SecureVaultOverview",
                        deviceCount: tabIndex==0 ? "\(vault.signers.count)" : nil
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
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
    }
    
    private func nextTapped() {        
        guard tabIndex<totalTabCount-1 else {
            moveToBackupView()
            return
        }
        
        tabIndex+=1
    }
    
    private func moveToBackupView() {
        isBackupLinkActive = true
    }
    
    private func animate(index: Int) {
        animationVM?.setInput("Index", value: Double(index))
    }
}

#Preview {
    SecureBackupVaultOverview(vault: Vault.example)
}
