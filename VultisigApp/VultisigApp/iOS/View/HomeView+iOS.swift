//
//  HomeView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension HomeView {
    var container: some View {
        ZStack {
            content
            
            if isLoading {
                Loader()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var content: some View {
        ZStack {
            Background()
            main
        }
        .alert(
            NSLocalizedString("newUpdateAvailable", comment: ""),
            isPresented: $phoneCheckUpdateViewModel.showUpdateAlert
        ) {
            Link(destination: StaticURL.AppStoreVultisigURL) {
                Text(NSLocalizedString("updateNow", comment: ""))
            }
            
            Button(NSLocalizedString("dismiss", comment: ""), role: .cancel) {}
        } message: {
            Text(phoneCheckUpdateViewModel.latestVersionString)
        }
    }
    
    var main: some View {
        view
    }
    
    var view: some View {
        VStack(spacing: 0) {
            ZStack {
                if let vault = viewModel.selectedVault {
                    VaultDetailView(showVaultsList: $showVaultsList, vault: vault)
                }
                
                VaultsView(
                    viewModel: viewModel,
                    showVaultsList: $showVaultsList,
                    isEditingVaults: $isEditingVaults, 
                    isEditingFolders: $isEditingFolders,
                    showFolderDetails: $showFolderDetails,
                    selectedFolder: $selectedFolder
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                leadingButton
            }
            ToolbarItem(placement: Placement.principal.getPlacement()) {
                navigationTitle
            }
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                editButton
            }
        }
        .toolbarBackground(Color.backgroundBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            setData()
        }
        .onFirstAppear {
            checkUpdate()
        }
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: Vault(name: "Main Vault"), selectedVault: viewModel.selectedVault)
        }
        .navigationDestination(isPresented: $shouldKeysignTransaction) {
            if let vault = viewModel.selectedVault {
                JoinKeysignView(vault: vault)
            }
        }
        .navigationDestination(isPresented: $vultExtensionViewModel.showImportView) {
            ImportWalletView()
        }
    }
    
    var leadingButton: some View {
        ZStack {
            if showFolderDetails && showVaultsList {
                backButtonForFolder
            } else {
                menuButton
            }
        }
    }
    
    var backButtonForFolder: some View {
        Button {
            showFolderDetails = false
        } label: {
            Image(systemName: "chevron.backward")
                .font(.body18MenloBold)
                .foregroundColor(.neutral0)
        }
    }
    
    func setData() {
        fetchVaults()
        shouldJoinKeygen = false
        shouldKeysignTransaction = false
        
        if let vault = selectedVault {
            viewModel.setSelectedVault(vault)
            selectedVault = nil
            return
        } else {
            viewModel.loadSelectedVault(for: vaults)
        }
        
        presetValuesForDeeplink()
    }
    
    func checkUpdate() {
        phoneCheckUpdateViewModel.checkForUpdates(isAutoCheck: true)
    }
}
#endif
