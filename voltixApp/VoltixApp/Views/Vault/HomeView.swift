//
//  HomeView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    var selectedVault: Vault? = nil
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @Query var vaults: [Vault]
    @StateObject var viewModel = HomeViewModel()
    
    @State var showVaultsList = false
    @State var isEditingVaults = false
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
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
        .onAppear {
            setData()
        }
        .navigationDestination(isPresented: $deeplinkViewModel.joinVaultActive) {
            SetupVaultView(tssType: deeplinkViewModel.tssType ?? .Keygen)
        }
    }
    
    var view: some View {
        ZStack {
            if let vault = viewModel.selectedVault {
                VaultDetailView(showVaultsList: $showVaultsList, vault: vault)
            }
            
            VaultsView(viewModel: viewModel, showVaultsList: $showVaultsList, isEditingVaults: $isEditingVaults)
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
        NavigationLink {
            SettingsView()
        } label: {
            NavigationMenuButton()
        }
    }
    
    var editButton: some View {
        NavigationHomeEditButton(
            vault: viewModel.selectedVault,
            showVaultsList: showVaultsList,
            isEditingVaults: $isEditingVaults
        )
    }
    
    private func setData() {
        if let vault = selectedVault {
            viewModel.setSelectedVault(vault)
            return
        }
        
        viewModel.loadSelectedVault(for: vaults)
        presetValuesForDeeplink()
    }
    
    private func presetValuesForDeeplink() {
        presentationMode.wrappedValue.dismiss()
        
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
        deeplinkViewModel.joinVaultActive = true
    }
    
    private func moveToVaultsView() {
        guard let vault = deeplinkViewModel.selectedVault else {
            return
        }
        
        viewModel.setSelectedVault(vault)
        showVaultsList = false
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
