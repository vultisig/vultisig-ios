//
//  AddFolderScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI
import SwiftData

struct AddFolderScreen: View {
    var onClose: () -> Void
    
    @Query var vaults: [Vault]
    @Query var folders: [Folder]
    
    @State var filteredVaults: [Vault] = []
    
    @StateObject var folderViewModel = CreateFolderViewModel()
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: HomeViewModel
    
    var body: some View {
        view
            .padding(.top, 24)
            .padding(.bottom, isIPadOS ? 24 : 0)
            .padding(.horizontal, 16)
            .onLoad(perform: setData)
    }
    
    var view: some View {
        ZStack(alignment: .bottom) {
            content
            saveButton
        }
    }
    
    var content: some View {
        VStack {
            header
            CommonTextField(
                text: $folderViewModel.name,
                label: "folderName".localized,
                placeholder: "enterVaultName".localized,
                error: $folderViewModel.folderNameError
            )
            List {
                CommonListHeaderView(title: "selectVaults".localized)
                vaultsList
            }
            .customSectionSpacing(0)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(Theme.colors.bgPrimary)
            .safeAreaInset(edge: .bottom, content: { Spacer().frame(height: 100) })
        }
    }
    
    var vaultsList: some View {
        ForEach(Array(filteredVaults.enumerated()), id: \.element) { index, vault in
            AddFolderVaultCellView(
                vault: vault,
                isSelected: folderViewModel.selectedVaults.contains(vault),
                onSelection: {
                    handleSelection(vault: vault, isSelected: $0)
                }
            )
            .commonListItemContainer(index: index, itemsCount: filteredVaults.count)
        }
    }
    
    var saveButton: some View {
        ListBottomSection {
            PrimaryButton(title: "save") {
                saveFolder()
            }
            .disabled(folderViewModel.saveButtonDisabled)
        }
    }
    
    var header: some View {
        HStack {
            HStack {}
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("addFolder".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title3)
            HStack {
                ToolbarButton(image: "x", type: .outline) {
                    onClose()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private extension AddFolderScreen {
    func setData() {
        viewModel.filterVaults(vaults: vaults, folders: folders)
        self.filteredVaults = viewModel.filteredVaults
    }

    func saveFolder() {
        guard folderViewModel.runChecks(folders) else {
            return
        }
        
        folderViewModel.setupFolder(folders.count)
        
        guard let vaultFolder = folderViewModel.vaultFolder else {
            folderViewModel.showErrorAlert()
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            modelContext.insert(vaultFolder)
            onClose()
        }
    }
    
    func handleSelection(vault: Vault, isSelected: Bool) {
        if isSelected {
            folderViewModel.selectedVaults.append(vault)
        } else {
            removeVault(vault)
        }
    }
    
    func removeVault(_ vault: Vault) {
        for index in 0..<folderViewModel.selectedVaults.count {
            if areVaultsSame(folderViewModel.selectedVaults[index], vault) {
                folderViewModel.selectedVaults.remove(at: index)
                return
            }
        }
    }
    
    func areVaultsSame(_ selectedVault: Vault, _ vault: Vault) -> Bool {
        selectedVault.name == vault.name && selectedVault.pubKeyECDSA == vault.pubKeyECDSA && selectedVault.pubKeyEdDSA == vault.pubKeyEdDSA
    }
}

#Preview {
    AddFolderScreen {}
    .environmentObject(HomeViewModel())
}
