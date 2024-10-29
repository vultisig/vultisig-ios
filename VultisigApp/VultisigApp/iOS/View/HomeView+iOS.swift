//
//  HomeView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension HomeView {
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
                    showFolderDetails: $showFolderDetails
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                menuButton
            }
            ToolbarItem(placement: Placement.principal.getPlacement()) {
                navigationTitle
            }
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                editButton
            }
        }
        .onAppear {
            setData()
        }
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: Vault(name: "Main Vault"))
        }
        .navigationDestination(isPresented: $shouldKeysignTransaction) {
            if let vault = viewModel.selectedVault {
                JoinKeysignView(vault: vault)
            }
        }
    }
    
    func setData() {
        fetchVaults()
        shouldJoinKeygen = false
        shouldKeysignTransaction = false
        
        phoneCheckUpdateViewModel.checkForUpdates(isAutoCheck: true)
        
        if let vault = selectedVault {
            viewModel.setSelectedVault(vault)
            selectedVault = nil
            return
        } else {
            viewModel.loadSelectedVault(for: vaults)
        }
        
        presetValuesForDeeplink()
    }
}
#endif
