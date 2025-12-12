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
        main
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PrimaryBackgroundWithGradient())
        .navigationBarBackButtonHidden(showBackButton ? false : true)
        .navigationDestination(isPresented: $showImportSeedphrase) {
            KeyImportOnboardingScreen()
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
        VStack(spacing: 0) {
            Spacer()
            VultisigLogo()
                .offset(y: 64)
            Spacer()
            buttons
        }
    }
    
    var buttons: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                scanButton
                importVaultButton
            }
            .opacity(showButtonStack ? 1 : 0)
            .offset(y: showButtonStack ? 0 : 50)
            .scaleEffect(showButtonStack ? 1 : 0.8)
            .blur(radius: showButtonStack ? 0 : 10)
            .animation(.spring(duration: 0.3), value: showButtonStack)
            newVaultButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }
    
    var newVaultButton: some View {
        PrimaryNavigationButton(title: "getStarted") {
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
    
    var importVaultButton: some View {
        ZStack(alignment: .center) {
            PrimaryButton(
                title: "import",
                leadingIcon: "arrow-down-circle",
                trailingIcon: "fake-icon",
                type: .secondary
            ) {
                // TODO: - Remove before seed phrase import release
                #if DEBUG
                showImportSelectionSheet = true
                #else
                showImportVaultShare = true
                #endif
            }
            
            // TODO: - Remove before seed phrase import release
            #if DEBUG
            newTag
                .offset(x: 48)
            #endif
        }
    }
    
    private var newTag: some View {
        HStack(spacing: 2) {
            Icon(
                named: "stars",
                color: Theme.colors.alertWarning,
                size: 8
            )
            Text("new")
                .foregroundStyle(Theme.colors.alertWarning)
                .font(FontStyle.brockmanMedium.size(8))
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
