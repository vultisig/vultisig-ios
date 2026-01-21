//
//  VaultListView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/09/2025.
//

import SwiftUI
import SwiftData

struct VaultListView: View {
    @Binding var isPresented: Bool
    @Binding var isEditing: Bool
    var onAddVault: () -> Void
    var onSelectVault: (Vault) -> Void
    var onSelectFolder: (Folder) -> Void
    var onAddFolder: () -> Void

    @Query(sort: \Vault.order, order: .forward) var vaults: [Vault]
    @Query(sort: \Folder.order, order: .forward) var folders: [Folder]

    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var appViewModel: AppViewModel

    var filteredVaults: [Vault] {
        homeViewModel.getFilteredVaults(vaults: vaults, folders: folders)
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
                    .padding(.bottom, 16)
                List {
                    sectionHeader(title: "folders".localized, paddingTop: 0)
                    foldersList
                    sectionHeader(title: "vaults".localized)
                    vaultsList
                }
                .customSectionSpacing(0)
                .listStyle(.plain)
                .buttonStyle(.borderless)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .background(Theme.colors.bgPrimary)
                .safeAreaInset(edge: .bottom, content: { Spacer().frame(height: isEditing ? 100 : 0) })
                .background(Theme.colors.bgPrimary)
            }
            addFolderButton
        }
        .padding(.top, 24)
        .padding(.bottom, isIPadOS ? 24 : 0)
        .padding(.horizontal, 16)
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
    }

    var editingHeader: some View {
        HStack {
            HStack {}
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("editVaults".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title3)

            HStack {
                ToolbarButton(image: "check", type: .confirmation) {
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
            #if os(macOS)
            ToolbarButton(image: "chevron-right", type: .outline) {
                isPresented.toggle()
            }
            .rotationEffect(.radians(.pi))
            #endif
            VStack(alignment: .leading, spacing: 4) {
                Text("vaults".localized)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.title3)
                Text(headerSubtitle)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.caption12)
            }
            Spacer()
            ToolbarButton(image: "pencil", type: .outline) {
                withAnimation {
                    isEditing.toggle()
                }
            }
            ToolbarButton(image: "plus", type: .confirmation, action: onAddVault)
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    var foldersList: some View {
        ForEach(folders) { folder in
            FolderCellView(
                folder: folder,
                selectedVaultName: appViewModel.selectedVault?.name,
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
        ForEach(filteredVaults) { vault in
            VaultCellView(
                vault: vault,
                isSelected: appViewModel.selectedVault == vault,
                isEditing: $isEditing) {
                    onSelectVault(vault)
                }
                .disabled(isEditing)
                .plainListItem()
                .background(Theme.colors.bgPrimary)
        }
        .onMove(perform: isEditing ? moveVaults : nil)
    }

    var addFolderButton: some View {
        ListBottomSection {
            PrimaryButton(
                title: "addFolder",
                leadingIcon: "folder-add",
                type: .secondary,
                action: onAddFolder
            )
        }
        .opacity(isEditing ? 1 : 0)
        .animation(.interpolatingSpring.delay(0.3), value: isEditing)
    }

    func sectionHeader(title: String, paddingTop: CGFloat? = nil) -> some View {
        CommonListHeaderView(title: title, paddingTop: paddingTop)
            .showIf(showListHeaders)
    }

    func moveVaults(from: IndexSet, to: Int) {
        var filteredVaults = filteredVaults.sorted(by: { $0.order < $1.order })
        filteredVaults.move(fromOffsets: from, toOffset: to)
        for (index, item) in filteredVaults.enumerated() {
            item.order = index
        }
        try? modelContext.save()
    }

    func moveFolder(from: IndexSet, to: Int) {
        var s = folders.sorted(by: { $0.order < $1.order })
        s.move(fromOffsets: from, toOffset: to)
        for (index, item) in s.enumerated() {
            item.order = index
        }
        try? modelContext.save()
    }
}

#Preview {
    VaultListView(
        isPresented: .constant(true),
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
    .environmentObject(AppViewModel())
}
