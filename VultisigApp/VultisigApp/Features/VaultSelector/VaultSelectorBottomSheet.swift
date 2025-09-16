//
//  VaultSelectorBottomSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftData
import SwiftUI

struct VaultSelectorBottomSheet: View {
    @Query(sort: \Vault.order, order: .forward) var vaults: [Vault]
    @Query(sort: \Folder.order, order: .forward) var folders: [Folder]
        
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var homeViewModel: HomeViewModel
    @StateObject var viewModel = VaultSelectorViewModel()
    
    var onAddVault: () -> Void
    var onSelectVault: (Vault) -> Void

    var headerSubtitle: String {
        let vaultsText: String = vaults.count > 1 ? "vaults".localized : "vault".localized
        var subtitle = "\(vaults.count) \(vaultsText)"
    
        if vaults.count > 1 {
            subtitle += " · \(homeViewModel.balanceText(for: vaults))"
        }
        
        return subtitle
    }
    
    var showListHeaders: Bool {
        viewModel.filteredVaults.count > 0 && folders.count > 0
    }
    
    var body: some View {
        VStack {
            header
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    foldersList
                    vaultsList
                }
            }
        }
        .padding(.top, 24)
        .padding(.horizontal, 16)
        .presentationDragIndicator(.visible)
        .presentationDetents(detents)
        .presentationBackground(Theme.colors.bgPrimary)
        .onAppear {
            viewModel.setup(folders: folders, vaults: vaults)
        }
    }
    
    var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("vaults".localized)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.title3)
                Text(headerSubtitle)
                    .foregroundStyle(Theme.colors.textExtraLight)
                    .font(Theme.fonts.caption12)
            }
            Spacer()
            TabBarAccessoryButton(icon: "plus", action: onAddVault)
        }
        .padding(.leading, 8)
    }
    
    @ViewBuilder
    var foldersList: some View {
        sectionHeader(title: "folders".localized)
        ForEach(viewModel.folders) { folder in
            FolderCellView(folder: folder, selectedVaultName: homeViewModel.selectedVault?.name) {
                // TODO: - Present Folder
            }
        }
    }
    
    @ViewBuilder
    var vaultsList: some View {
        sectionHeader(title: "vaults".localized)
        ForEach(viewModel.filteredVaults) { vault in
            VaultCellView(vault: vault, isSelected: homeViewModel.selectedVault == vault) {
                onSelectVault(vault)
            }
        }
    }
    
    func sectionHeader(title: String) -> some View {
        Text(title)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textExtraLight)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .padding(.top, 12)
            .showIf(showListHeaders)
    }
}

extension VaultSelectorBottomSheet {
    var detents: Set<PresentationDetent> {
        if vaults.count >= 8 || folders.count >= 4 {
            return [.medium, .large]
        }
        
        switch vaults.count {
        case 1:
            return [.height(214)]
        case 2:
            return [.height(278)]
        default:
            return [.medium]
        }
    }
}

#Preview {
    struct PreviewContainer: View {
        @State var isPresented: Bool = false
        
       var body: some View {
           VStack {
               Button("Open Sheet") {
                   isPresented.toggle()
               }
           }
           .sheet(isPresented: $isPresented) {
               VaultSelectorBottomSheet(
                onAddVault: {},
                onSelectVault: { _ in }
               )
           }
           .background(Theme.colors.bgPrimary)
        }
    }

    return PreviewContainer()
        .environmentObject(HomeViewModel())
}
