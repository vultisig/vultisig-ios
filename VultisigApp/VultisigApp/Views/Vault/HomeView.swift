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
        if let selectedVault = viewModel.selectedVault {
            VaultMainScreen(vault: selectedVault)
        } else {
            VStack {}.onAppear { setData() }
        }
//        container
//            .alert(
//                NSLocalizedString("newUpdateAvailable", comment: ""),
//                isPresented: $phoneCheckUpdateViewModel.showUpdateAlert
//            ) {
//                Link(destination: StaticURL.AppStoreVultisigURL) {
//                    Text(NSLocalizedString("updateNow", comment: ""))
//                }
//                
//                Button(NSLocalizedString("dismiss", comment: ""), role: .cancel) {}
//            } message: {
//                Text(phoneCheckUpdateViewModel.latestVersionString)
//            }
    }
    
    var navigationTitle: some View {
        HStack {
            title
            
            if viewModel.selectedVault != nil {
                Image(systemName: "chevron.up")
                    .font(Theme.fonts.caption10)
                    .bold()
                    .foregroundColor(Theme.colors.textPrimary)
                    .rotationEffect(.degrees(showVaultsList ? 0 : 180))
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
        .foregroundColor(Theme.colors.textPrimary)
        .font(.body)
    }
    
    var menuButton: some View {
        NavigationLink {
            SettingsMainScreen()
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
    
    func checkUpdate() {
        phoneCheckUpdateViewModel.checkForUpdates(isAutoCheck: true)
    }
}

#Preview {
    HomeView()
        .environmentObject(DeeplinkViewModel())
        .environmentObject(HomeViewModel())
        .environmentObject(PhoneCheckUpdateViewModel())
}
