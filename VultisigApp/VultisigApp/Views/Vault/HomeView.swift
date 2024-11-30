//
//  HomeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @State var selectedVault: Vault? = nil
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var viewModel: HomeViewModel
    @EnvironmentObject var phoneCheckUpdateViewModel: PhoneCheckUpdateViewModel
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    @EnvironmentObject var macCameraServiceViewModel: MacCameraServiceViewModel
    @EnvironmentObject var macCheckUpdateViewModel: MacCheckUpdateViewModel
    
    @State var vaults: [Vault] = []
    
    @State var showMenu = false
    @State var isLoading = false
    @State var didUpdate = true
    @State var showVaultsList = false
    @State var isEditingVaults = false
    @State var isEditingFolders = false
    @State var shouldJoinKeygen = false
    @State var showFolderDetails = false
    @State var shouldImportBackup = false
    @State var shouldKeysignTransaction = false
    
    @State var selectedFolder: Folder = Folder.example
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            content
            
            if isLoading {
                Loader()
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
            Text(NSLocalizedString(showFolderDetails ? selectedFolder.folderName : "vaults", comment: "Vaults"))
            Text(viewModel.selectedVault?.name ?? NSLocalizedString("vault", comment: "Home view title"))
        }
        .offset(y: showVaultsList ? 9 : -10)
        .frame(height: 20)
        .clipped()
        .bold()
        .foregroundColor(.neutral0)
        .font(.body)
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
            selectedFolder: selectedFolder,
            isEditingVaults: $isEditingVaults,
            isEditingFolders: $isEditingFolders,
            showFolderDetails: $showFolderDetails
        )
    }
    
    func presetValuesForDeeplink() {
        if let _ = vultExtensionViewModel.documentData {
            shouldImportBackup = true
        }
        
        guard let type = deeplinkViewModel.type else {
            return
        }
        deeplinkViewModel.type = nil
        
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
        showVaultsList = false
        shouldJoinKeygen = true
    }
    
    private func moveToVaultsView() {
        isLoading = true
        
        guard let vault = deeplinkViewModel.selectedVault else {
            return
        }
        
        viewModel.setSelectedVault(vault)
        showVaultsList = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            shouldKeysignTransaction = true
            isLoading = false
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
    
    func fetchVaults() {
        let fetchVaultDescriptor = FetchDescriptor<Vault>()
        do {
            vaults = try modelContext.fetch(fetchVaultDescriptor)
        } catch {
            print(error)
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(DeeplinkViewModel())
        .environmentObject(HomeViewModel())
        .environmentObject(MacCameraServiceViewModel())
        .environmentObject(MacCheckUpdateViewModel())
}
