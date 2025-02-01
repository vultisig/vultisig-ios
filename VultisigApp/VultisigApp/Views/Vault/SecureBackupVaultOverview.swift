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
    @State var isLinkActive = false
    
    let totalTabCount = 2
    
    let animationVM = RiveViewModel(fileName: "Onboarding", autoPlay: true)
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .navigationDestination(isPresented: $isLinkActive) {
            BackupVaultNowView(vault: vault)
        }
    }
    
    var content: some View {
        VStack(spacing: 0) {
            header
            progressBar
            Spacer()
            text
            button
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
    
    var text: some View {
        TabView(selection: $tabIndex) {
            ForEach(0..<totalTabCount, id: \.self) { index in
                VStack {
                    Spacer()
                    OnboardingTextCard(
                        index: index,
                        textPrefix: "SecureVaultOverview",
                        animationVM: animationVM,
                        deviceCount: tabIndex==0 ? "\(vault.signers.count)" : nil
                    )
                }
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .frame(maxWidth: .infinity)
    }
    
    var button: some View {
        nextButton
            .padding(.horizontal, 40)
            .padding(.bottom, 10)
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
        guard tabIndex<totalTabCount-1 else {
            moveToBackupView()
            return
        }
        
        tabIndex+=1
    }
    
    private func moveToBackupView() {
        isLinkActive = true
    }
}

#Preview {
    SecureBackupVaultOverview(vault: Vault.example)
}
