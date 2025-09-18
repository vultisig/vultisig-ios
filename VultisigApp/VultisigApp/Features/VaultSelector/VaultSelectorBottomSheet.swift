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
    
    var filteredVaults: [Vault] {
        let vaultNames = Set(folders.flatMap { $0.containedVaultNames })
        return vaults.filter { !vaultNames.contains($0.name) }
    }
        
    @State var isEditing: Bool = false
    
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
        filteredVaults.count > 0 && folders.count > 0
    }
    
    var body: some View {
        VStack {
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
        .padding(.top, 24)
        .padding(.horizontal, 16)
        .presentationDragIndicator(.visible)
        .presentationDetents(detents)
        .presentationBackground(Theme.colors.bgPrimary)
        .onAppear {
//            viewModel.setup(folders: folders, vaults: vaults)
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
                // TODO: - Present Folder
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

extension VaultSelectorBottomSheet {
    var detents: Set<PresentationDetent> {
        if isEditing {
            return [.medium, .large]
        }
        
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

struct BottomSheetButton: View {
    let icon: String
    let type: ButtonType
    var action: () -> Void
    
    init(icon: String, type: ButtonType = .primary, action: @escaping () -> Void) {
        self.icon = icon
        self.type = type
        self.action = action
    }
    
    var backgroundColor: Color {
        switch type {
        case .primary:
            Theme.colors.primaryAccent4
        case .secondary:
            Theme.colors.bgSecondary
        case .alert:
            Theme.colors.alertError
        }
    }
    
    var is26: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        } else {
            return false
        }
    }
    
    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            button
                .glassEffect(.regular.tint(backgroundColor).interactive())
        } else {
            button
        }
    }
    
    var button: some View {
        Button(action: action) {
            Icon(named: icon, color: Theme.colors.textPrimary, size: 20)
                .padding(12)
                .background(is26 ? nil : Circle().fill(backgroundColor))
                .overlay(Circle().inset(by: 0.5).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        }
    }
}

