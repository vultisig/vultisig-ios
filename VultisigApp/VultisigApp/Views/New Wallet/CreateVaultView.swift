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
    @State var showImportSelectionSheet: Bool = false
    @State var showImportSeedphrase: Bool = false
    @State var showImportVaultShare: Bool = false
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appViewModel: AppViewModel
    
    init(selectedVault: Vault? = nil, showBackButton: Bool = false) {
        self.selectedVault = selectedVault
        self.showBackButton = showBackButton
    }

    var body: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(showBackButton ? false : true)
        .navigationDestination(isPresented: $showImportSeedphrase) {
            ImportSeedphraseScreen()
        }
        .navigationDestination(isPresented: $showImportVaultShare) {
            ImportVaultShareScreen()
        }
        .crossPlatformSheet(isPresented: $showImportSelectionSheet) {
            ImportVaultSelectionSheet(isPresented: $showImportSelectionSheet) {
                showImportSelectionSheet = false
                showImportSeedphrase = true
            } onVaultShare: {
                showImportSelectionSheet = false
                showImportVaultShare = true
            }
        }
        .onLoad {
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
            if appViewModel.showOnboarding {
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
                .foregroundColor(Theme.colors.textPrimary)
                .font(Theme.fonts.caption12)
            
            Separator()
        }
        .opacity(showSeparator ? 1 : 0)
        .offset(y: showSeparator ? 0 : 50)
        .scaleEffect(showSeparator ? 1 : 0.8)
        .blur(radius: showSeparator ? 0 : 10)
        .animation(.spring(duration: 0.3), value: showSeparator)
    }
    
    var importVaultButton: some View {
        PrimaryButton(title: "importVault", type: .secondary) {
            // TODO: - Remove before seed phrase import release
            #if DEBUG
            showImportSelectionSheet = true
            #else
            showImportVaultShare = true
            #endif
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
        .environmentObject(AppViewModel())
}
