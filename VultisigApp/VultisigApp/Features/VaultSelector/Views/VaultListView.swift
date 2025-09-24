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
    var onAddFolder: () -> Void
    
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
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                List {
                    foldersList
                    vaultsList
                }
                .listSectionSpacing(0)
                .listRowSpacing(0)
                .listStyle(.grouped)
                .buttonStyle(.borderless)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .padding(.bottom, isEditing ? 100 : 0)
                .background(Theme.colors.bgPrimary)
                .padding(.top, 20)
            }
            addFolderButton
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
        .transition(.opacity.animation(.interpolatingSpring))
        .background(
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Theme.colors.bgPrimary, location: 0.50),
                    Gradient.Stop(color: Theme.colors.bgPrimary.opacity(0.5), location: 0.85),
                    Gradient.Stop(color: Theme.colors.bgPrimary.opacity(0), location: 1.00),
                ],
                startPoint: UnitPoint(x: 0.5, y: 0),
                endPoint: UnitPoint(x: 0.5, y: 1)
            )
        )
    }
    
    var editingHeader: some View {
        HStack {
            HStack {}
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("editVaults".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title3)
            
            HStack {
                BottomSheetButton(icon: "check") {
                    withAnimation {
                        isEditing.toggle()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
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
        Section {
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
        } header: {
            sectionHeader(title: "folders".localized)
                .plainListItem()
        }
        .listSectionSpacing(0)
    }
    
    @ViewBuilder
    var vaultsList: some View {
        Section {
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
        } header: {
            sectionHeader(title: "vaults".localized)
                .plainListItem()
        }
        .listSectionSpacing(0)
    }
    
    var addFolderButton: some View {
        PrimaryButton(
            title: "addFolder",
            leadingIcon: "folder-add",
            type: .secondary,
            action: onAddFolder
        )
        .padding(.vertical, 16)
        .background(Theme.colors.bgPrimary)
        .transition(.opacity)
        .showIf(isEditing)
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
        }, onAddFolder: {
        }
    )
    .environmentObject(HomeViewModel())
}
