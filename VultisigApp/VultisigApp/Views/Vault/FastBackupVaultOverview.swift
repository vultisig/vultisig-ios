//
//  FastBackupVaultOverview.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-01.
//

import SwiftUI
import RiveRuntime

struct FastBackupVaultOverview: View {
    let vault: Vault
    let selectedTab: SetupVaultState?
    let email: String
    @ObservedObject var viewModel: KeygenViewModel
    
    @State var tabIndex = 0
    @State var isVerificationLinkActive = false
    @State var isBackupLinkActive = false

    let totalTabCount = 3
    
    @State var animationVM: RiveViewModel? = nil
    
    var body: some View {
        ZStack {
            Background()
            animation
            container
        }
        .sheet(isPresented: $isVerificationLinkActive) {
            ServerBackupVerificationView(
                vault: vault,
                email: email,
                isPresented: $isVerificationLinkActive,
                isBackupLinkActive: $isBackupLinkActive
            )
        }
        .navigationDestination(isPresented: $isBackupLinkActive) {
            BackupSetupView(vault: vault, isNewVault: true)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                animationVM = RiveViewModel(fileName: "fastvault_overview", autoPlay: true)
            }
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
        ZStack{
            if let animationVM {
                animationVM.view()
            } else {
                Spacer()
            }
        }
        .offset(y: -100)
    }
    
    var text: some View {
        TabView(selection: $tabIndex) {
            ForEach(0..<totalTabCount, id: \.self) { index in
                VStack {
                    Spacer()
                    OnboardingTextCard(
                        index: index,
                        textPrefix: "FastVaultOverview",
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
        guard tabIndex < totalTabCount-1 else {
            isVerificationLinkActive = true
            return
        }
        
        tabIndex += 1
    }
    
    private func moveToBackupView() {
        isVerificationLinkActive = true
    }
    
    private func animate(index: Int) {
        animationVM?.setInput("Index", value: Double(index))
    }
}

#Preview {
    FastBackupVaultOverview(
        vault: Vault.example,
        selectedTab: .secure,
        email: "mail@email.com",
        viewModel: KeygenViewModel()
    )
}
