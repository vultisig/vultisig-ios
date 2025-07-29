//
//  CreateVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct CreateVaultView: View {
    let selectedVault: Vault?
    var showBackButton = false
    
    @State var showNewVaultButton = false
    @State var showSeparator = false
    @State var showButtonStack = false
    @State var showSheet = false
    @State var shouldJoinKeygen = false
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var accountViewModel: AccountViewModel

    var body: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(showBackButton ? false : true)
        .onFirstAppear {
            setData()
        }
    }
    
    var headerMac: some View {
        CreateVaultHeader(showBackButton: showBackButton)
    }
    
    var view: some View {
        VStack {
            Spacer()
            VultisigLogo()
            Spacer()
            buttons
        }
    }
    
    var buttons: some View {
        VStack(spacing: 16) {
            newVaultButton
            orSeparator
            Group {
                scanButton
                importVaultButton
            }
            .opacity(showButtonStack ? 1 : 0)
            .offset(y: showButtonStack ? 0 : 50)
            .scaleEffect(showButtonStack ? 1 : 0.8)
            .blur(radius: showButtonStack ? 0 : 10)
            .animation(.spring(duration: 0.3), value: showButtonStack)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }
    
    var newVaultButton: some View {
        PrimaryNavigationButton(title: "createNewVault") {
            if accountViewModel.showOnboarding {
                OnboardingView()
            } else {
                SetupQRCodeView(tssType: .Keygen, vault: nil)
            }
        }
        .opacity(showNewVaultButton ? 1 : 0)
        .offset(y: showNewVaultButton ? 0 : 20)
        .scaleEffect(showNewVaultButton ? 1 : 0.8)
        .animation(.spring(duration: 0.3), value: showNewVaultButton)
    }
    
    var orSeparator: some View {
        HStack(spacing: 16) {
            Separator()
            
            Text(NSLocalizedString("or", comment: ""))
                .foregroundColor(.neutral0)
                .font(.body12BrockmannMedium)
            
            Separator()
        }
        .opacity(showSeparator ? 1 : 0)
        .offset(y: showSeparator ? 0 : 50)
        .scaleEffect(showSeparator ? 1 : 0.8)
        .blur(radius: showSeparator ? 0 : 10)
        .animation(.spring(duration: 0.3), value: showSeparator)
    }
    
    var importVaultButton: some View {
        PrimaryNavigationButton(title: "importVault", type: .secondary) {
            ImportWalletView()
        }
    }
    
    private func setData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showNewVaultButton = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showSeparator = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showButtonStack = true
        }
    }
    
    func createVault() -> Vault {
        let vaultName = Vault.getUniqueVaultName(modelContext: modelContext)
        return Vault(name: vaultName)
    }
}

#Preview {
    CreateVaultView(selectedVault: Vault.example)
        .environmentObject(AccountViewModel())
}
