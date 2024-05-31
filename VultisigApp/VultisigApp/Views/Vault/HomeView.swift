//
//  HomeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    var selectedVault: Vault? = nil
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    
    @Query var vaults: [Vault]
    @StateObject var viewModel = HomeViewModel()
    
    @State var showVaultsList = false
    @State var isEditingVaults = false
    @State var isEditingChains = false
    @State var showMenu = false
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
    
    var body: some View {
        ZStack {
            Background()
            
            if showMenu {
                SettingsView(showMenu: $showMenu, homeViewModel: viewModel)
            } else {
                view
            }
        }
    }
    
    var view: some View {
        ZStack {
            if let vault = viewModel.selectedVault {
                VaultDetailView(showVaultsList: $showVaultsList, isEditingChains: $isEditingChains, vault: vault)
            }
            
            VaultsView(viewModel: viewModel, showVaultsList: $showVaultsList, isEditingVaults: $isEditingVaults)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                menuButton
            }
            
            ToolbarItem(placement: .principal) {
                navigationTitle
            }

            ToolbarItem(placement: .topBarTrailing) {
                editButton
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            setData()
        }
        .onFirstAppear {
            onFirstAppear()
        }
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: Vault(name: "Main Vault"), shouldJoinKeygen: shouldJoinKeygen)
        }
        .navigationDestination(isPresented: $shouldKeysignTransaction) {
            if let vault = viewModel.selectedVault {
                JoinKeysignView(vault: vault, shouldKeysignTransaction: shouldKeysignTransaction)
            }
        }
    }
    
    var navigationTitle: some View {
        ZStack {
            HStack {
                title
                
                if viewModel.selectedVault != nil {
                    Image(systemName: "chevron.up")
                        .font(.body8Menlo)
                        .bold()
                        .foregroundColor(.neutral0)
                        .rotationEffect(.degrees(showVaultsList ? 0 : 180))
                }
            }
        }
        .onTapGesture {
            switchView()
        }
    }
    
    var title: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("vaults", comment: "Vaults"))
                .font(.body)
                .bold()
                .foregroundColor(.neutral0)
            
            Text(viewModel.selectedVault?.name ?? NSLocalizedString("vault", comment: "Home view title"))
                .font(.body)
                .bold()
                .foregroundColor(.neutral0)
        }
        .offset(y: showVaultsList ? 9 : -10)
        .frame(height: 20)
        .clipped()
    }
    
    var menuButton: some View {
        Button {
            showMenu.toggle()
        } label: {
            NavigationMenuButton()
        }

    }
    
    var editButton: some View {
        NavigationHomeEditButton(
            vault: viewModel.selectedVault,
            showVaultsList: showVaultsList,
            isEditingVaults: $isEditingVaults, 
            isEditingChains: $isEditingChains
        )
    }
    
    private func setData() {
        shouldJoinKeygen = false
        shouldKeysignTransaction = false
        
        viewModel.loadSelectedVault(for: vaults)
        presetValuesForDeeplink()
    }
    
    private func onFirstAppear() {
        if let vault = selectedVault {
            viewModel.setSelectedVault(vault)
        }
    }
    
    private func presetValuesForDeeplink() {
        guard let type = deeplinkViewModel.type else {
            return
        }
        
        switch type {
        case .NewVault:
            moveToCreateVaultView()
        case .SignTransaction:
            moveToVaultsView()
        case .Unknown:
            return
        }
    }
    
    private func moveToCreateVaultView() {
        showVaultsList = true
        shouldJoinKeygen = true
    }
    
    private func moveToVaultsView() {
        guard let vault = deeplinkViewModel.selectedVault else {
            return
        }
        
        viewModel.setSelectedVault(vault)
        showVaultsList = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldKeysignTransaction = true
        }
    }
    
    private func switchView() {
        guard viewModel.selectedVault != nil else {
            return
        }
        
        withAnimation(.easeInOut) {
            showVaultsList.toggle()
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(DeeplinkViewModel())
}
