//
//  HomeView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension HomeView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .alert(
            NSLocalizedString("newUpdateAvailable", comment: ""),
            isPresented: $macCheckUpdateViewModel.showUpdateAlert
        ) {
            Link(destination: URL(string: Endpoint.githubMacUpdateBase + macCheckUpdateViewModel.latestVersionBase)!) {
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
            showVaultsList: $showVaultsList,
            isEditingVaults: $isEditingVaults
        )
    }
    
    var view: some View {
        VStack(spacing: 0) {
            ZStack {
                if let vault = viewModel.selectedVault {
                    VaultDetailView(showVaultsList: $showVaultsList, vault: vault)
                }
                
                VaultsView(viewModel: viewModel, showVaultsList: $showVaultsList, isEditingVaults: $isEditingVaults)
            }
        }
        .navigationBarBackButtonHidden(true)
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
     
        macCameraServiceViewModel.stopSession()
        macCheckUpdateViewModel.checkForUpdates(isAutoCheck: true)
        
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
