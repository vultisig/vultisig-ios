//
//  VaultListView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/09/2025.
//

import SwiftUI
import SwiftData

struct VaultListView: View {
    @Binding var isEditing: Bool
    var onAddVault: () -> Void
    var onSelectVault: (Vault) -> Void
    var onSelectFolder: (Folder) -> Void
    
    @Query(sort: \Vault.order, order: .forward) var vaults: [Vault]
    @Query(sort: \Folder.order, order: .forward) var folders: [Folder]
    
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var homeViewModel: HomeViewModel
    @StateObject var viewModel = VaultSelectorViewModel()
    
    var filteredVaults: [Vault] {
        let vaultNames = Set(folders.flatMap { $0.containedVaultNames })
        return vaults.filter { !vaultNames.contains($0.name) }
    }
    
    var headerSubtitle: String {
        let vaultsText: String = vaults.count > 1 ? "vaults".localized : "vault".localized
        var subtitle = "\(vaults.count) \(vaultsText)"
    
        if vaults.count > 1 {
            subtitle += " · \(homeViewModel.balanceText(for: vaults))"
        }
        
        return subtitle
    }
    
    var showListHeaders: Bool {
        filteredVaults.count > 0 && folders.count > 0
    }
    
    var body: some View {
        VStack(spacing: 20) {
            header
            List {
                foldersList
                vaultsList
            }
            .listSectionSpacing(0)
            .listStyle(.plain)
            .buttonStyle(.borderless)
            .scrollContentBackground(.hidden)
            .background(Theme.colors.bgPrimary)
        }
    }
    
    var header: some View {
        Group {
            if isEditing {
                editingHeader
            } else {
                defaultHeader
            }
        }
        .transition(.opacity)
    }
    
    var editingHeader: some View {
        HStack {
            Spacer()
            Text("editVaults".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title3)
            Spacer()
            BottomSheetButton(icon: "check") {
                withAnimation {
                    isEditing.toggle()
                }
            }
        }
    }
    
    var defaultHeader: some View {
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
            BottomSheetButton(icon: "pencil", type: .secondary) {
                withAnimation {
                    isEditing.toggle()
                }
            }
            BottomSheetButton(icon: "plus", action: onAddVault)
        }
        .padding(.leading, 8)
    }
    
    @ViewBuilder
    var foldersList: some View {
        ForEach(folders) { folder in
            FolderCellView(
                folder: folder,
                selectedVaultName: homeViewModel.selectedVault?.name,
                isEditing: $isEditing
            ) {
                onSelectFolder(folder)
            }
            .disabled(isEditing)
            .plainListItem()
            .background(Theme.colors.bgPrimary)
        }
        .onMove(perform: isEditing ? moveFolder : nil)
    }
    
    @ViewBuilder
    var vaultsList: some View {
        sectionHeader(title: "vaults".localized)
            .plainListItem()
        ForEach(filteredVaults) { vault in
            VaultCellView(
                vault: vault,
                isSelected: homeViewModel.selectedVault == vault,
                isEditing: $isEditing) {
                onSelectVault(vault)
            }
            .disabled(isEditing)
            .plainListItem()
            .background(Theme.colors.bgPrimary)
        }
        .onMove(perform: isEditing ? moveVaults : nil)
    }
    
    func sectionHeader(title: String) -> some View {
        Text(title)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textExtraLight)
            .padding(.horizontal, 8)
            .showIf(showListHeaders)
    }
    
    func moveVaults(from: IndexSet, to: Int) {
        var filteredVaults = filteredVaults.sorted(by: { $0.order < $1.order })
        filteredVaults.move(fromOffsets: from, toOffset: to)
        for (index, item) in filteredVaults.enumerated() {
            item.order = index
        }
    }
    
    func moveFolder(from: IndexSet, to: Int) {
        var s = folders.sorted(by: { $0.order < $1.order })
        s.move(fromOffsets: from, toOffset: to)
        for (index, item) in s.enumerated() {
            item.order = index
        }
        try? self.modelContext.save()
    }
}

#Preview {
    VaultListView(
        isEditing: .constant(false),
        onAddVault: {
        },
        onSelectVault: {_ in
        },
        onSelectFolder: { _ in
        }
    )
    .environmentObject(HomeViewModel())
}
