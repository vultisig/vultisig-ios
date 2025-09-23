//
//  EditFolderScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/09/2025.
//

import SwiftUI
import SwiftData

struct EditFolderScreen: View {
    let folder: Folder
    
    @Query var folders: [Folder]
    @Query var vaults: [Vault]
    
    @State var folderName: String = ""
    @StateObject var folderViewModel = FolderDetailViewModel()
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: HomeViewModel
    
    var body: some View {
        view
            .padding(.top, 24)
            .padding(.horizontal, 16)
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.colors.bgPrimary)
            .alert(isPresented: $folderViewModel.showAlert) {
                alert
            }
            .onLoad {
                setData()
            }
            .onChange(of: folder.containedVaultNames) { oldValue, newValue in
                setData()
            }
    }
    
    var view: some View {
        ZStack(alignment: .bottom) {
            content
            saveButton
        }
    }
    
    var content: some View {
        List {
            CommonTextField(
                text: $folderName,
                label: "folderName".localized,
                placeholder: "typeHere".localized,
            )
            .plainListItem()
            .onLoad(perform: setupFolder)
            
            sectionHeader(title: "activeVaults".localized)
            selectedVaultsList
            sectionHeader(title: "available".localized)
                .showIf(!folderViewModel.remaningVaults.isEmpty)
            vaultsList
        }
        .listSectionSpacing(0)
        .listStyle(.plain)
        .buttonStyle(.borderless)
        .scrollContentBackground(.hidden)
        .background(Theme.colors.bgPrimary)
    }
    
    var selectedVaultsList: some View {
        ForEach(folderViewModel.selectedVaults.sorted(by: {
            $0.order < $1.order
        }), id: \.self) { vault in
            VaultFolderCellView(
                vault: vault,
                isOnFolder: true,
                isSelected: viewModel.selectedVault == vault,
                onSelection: { removeVault(vault) }
            )
            .plainListItem()
            .disabled(folderViewModel.selectedVaults.count == 1)
        }
        .onMove(perform: move)
    }
    
    var vaultsList: some View {
        ForEach(folderViewModel.remaningVaults, id: \.self) { vault in
            VaultFolderCellView(
                vault: vault,
                isOnFolder: false,
                isSelected: viewModel.selectedVault == vault,
                onSelection: { selectVault(vault) }
            )
            .plainListItem()
        }
    }
    
    var saveButton: some View {
        PrimaryButton(title: "saveChanges") {
            saveFolder()
        }
        .padding(16)
        .edgesIgnoringSafeArea(.bottom)
        .frame(maxHeight: nil)
        .clipped()
        .background(Theme.colors.bgPrimary)
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(folderViewModel.alertTitle, comment: "")),
            message: Text(NSLocalizedString(folderViewModel.alertDescription, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    func sectionHeader(title: String) -> some View {
        Text(title)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textExtraLight)
            .padding(.horizontal, 8)
            .plainListItem()
    }
    
    private func setData() {
        filterVaults()
        folderViewModel.setData(
            vaults: vaults,
            vaultFolder: folder,
            filteredVaults: viewModel.filteredVaults
        )
    }
    
    private func filterVaults() {
        viewModel.filterVaults(vaults: vaults, folders: folders)
    }
    
    private func handleVaultSelection(for vault: Vault) {
        removeVault(vault)
        filterVaults()
    }
    
    private func move(from: IndexSet, to: Int) {
        var s = folderViewModel.selectedVaults.sorted(by: { $0.order < $1.order })
        s.move(fromOffsets: from, toOffset: to)
        for (index, item) in s.enumerated() {
            item.order = index
        }
        try? self.modelContext.save()
    }
    
    private func selectVault(_ vault: Vault) {
        folderViewModel.selectedVaults.append(vault)
        folder.containedVaultNames = folderViewModel.selectedVaults.map({ vault in
            vault.name
        })
    }
    
    private func removeVault(_ vault: Vault) {
        let count = folderViewModel.selectedVaults.count
        
        guard count > 1 else {
            folderViewModel.toggleAlert()
            return
        }
        
        folderViewModel.removeVaultAtIndex(count: count, vault: vault)
        
        folder.containedVaultNames = folderViewModel.selectedVaults.map({ vault in
            vault.name
        })
    }
    
    private func setupFolder() {
        folderName = folder.folderName
    }
    
    private func saveFolder() {
        filterVaults()
        folder.folderName = folderName

        dismiss()
    }
}

#Preview {
    EditFolderScreen(
        folder: Folder.example
    )
    .environmentObject(HomeViewModel())
}
