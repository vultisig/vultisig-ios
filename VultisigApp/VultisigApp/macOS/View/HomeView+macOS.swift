//
//  HomeView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension HomeView {
    var container: some View {
        ZStack {
            content
            
            if isLoading {
                Loader()
            }
        }
    }
    
    var content: some View {
        ZStack {
            Background()
            main
        }
        .alert(
            NSLocalizedString("newUpdateAvailable", comment: ""),
            isPresented: $macCheckUpdateViewModel.showUpdateAlert
        ) {
            Link(destination: URL(string: Endpoint.githubMacDownloadBase + macCheckUpdateViewModel.latestVersionBase + macCheckUpdateViewModel.latestPackageName)!) {
                Text(NSLocalizedString("updateNow", comment: ""))
            }
            
            Button(NSLocalizedString("dismiss", comment: ""), role: .cancel) {}
        } message: {
            Text(macCheckUpdateViewModel.latestVersion)
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            Separator()
            view
        }
    }
    
    var headerMac: some View {
        HomeHeader(
            showFolderDetails: $showFolderDetails,
            showVaultsList: $showVaultsList,
            isEditingVaults: $isEditingVaults, 
            isEditingFolders: $isEditingFolders,
            selectedFolder: $selectedFolder
        )
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
        .onAppear {
            setData()
        }
        .onLoad {
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
        .navigationDestination(isPresented: $shouldImportBackup) {
            ImportWalletView()
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
        macCheckUpdateViewModel.checkForUpdates(isAutoCheck: true)
    }
}
#endif
