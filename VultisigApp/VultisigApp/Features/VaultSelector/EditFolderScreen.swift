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
    var onDelete: (Folder) -> Void
    
    @Query var folders: [Folder]
    @Query var vaults: [Vault]
    
    @State var folderName: String = ""
    @State var disableSelection: Bool = false
    @StateObject var folderViewModel = FolderDetailViewModel()
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: HomeViewModel
    
    var saveButtonDisabled: Bool {
        folderName.isEmpty
    }
    
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
                    .showIf(!folderViewModel.remainingVaults.isEmpty)
                vaultsList
            }
            .listSectionSpacing(0)
            .listStyle(.plain)
            .buttonStyle(.borderless)
            .scrollContentBackground(.hidden)
            .background(Theme.colors.bgPrimary)
            .animation(.interpolatingSpring, value: folder.containedVaultNames)
        }
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
            .disabled(disableSelection)
        }
        .onMove(perform: move)
    }
    
    var vaultsList: some View {
        ForEach(folderViewModel.remainingVaults, id: \.self) { vault in
            VaultFolderCellView(
                vault: vault,
                isOnFolder: false,
                isSelected: viewModel.selectedVault == vault,
                onSelection: { addVault(vault) }
            )
            .plainListItem()
        }
    }
    
    var saveButton: some View {
        PrimaryButton(title: "saveChanges") {
            saveFolder()
        }
        .edgesIgnoringSafeArea(.bottom)
        .frame(maxHeight: nil)
        .clipped()
        .background(
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Theme.colors.bgPrimary, location: 0.50),
                    Gradient.Stop(color: Theme.colors.bgPrimary.opacity(0.5), location: 0.85),
                    Gradient.Stop(color: Theme.colors.bgPrimary.opacity(0), location: 1.00),
                ],
                startPoint: UnitPoint(x: 0.5, y: 1),
                endPoint: UnitPoint(x: 0.5, y: 0)
            )
        )
        .disabled(saveButtonDisabled)
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
    
    var header: some View {
        HStack {
            HStack {}
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("editFolder".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title3)
            HStack {
                BottomSheetButton(icon: "trash", type: .alert) {
                    deleteFolder()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    
    private func setData() {
        viewModel.filterVaults(vaults: vaults, folders: folders)
        folderViewModel.setData(
            vaults: vaults,
            vaultFolder: folder,
            filteredVaults: viewModel.filteredVaults
        )
        updateSelection()
    }
    
    private func move(from: IndexSet, to: Int) {
        var s = folderViewModel.selectedVaults.sorted(by: { $0.order < $1.order })
        s.move(fromOffsets: from, toOffset: to)
        for (index, item) in s.enumerated() {
            item.order = index
        }
        try? self.modelContext.save()
    }
    
    private func addVault(_ vault: Vault) {
        folderViewModel.addVault(vault: vault)
        updateFolder()
    }
    
    private func removeVault(_ vault: Vault) {
        let count = folderViewModel.selectedVaults.count
        
        guard count > 1 else {
            folderViewModel.toggleAlert()
            return
        }
        
        folderViewModel.removeVault(vault: vault)
        updateFolder()
    }
    
    func updateFolder() {
        folder.containedVaultNames = folderViewModel.selectedVaults.map(\.name)
        updateSelection()
    }
    
    func updateSelection() {
        disableSelection = folderViewModel.selectedVaults.count == 1
    }
    
    private func setupFolder() {
        folderName = folder.folderName
    }
    
    private func saveFolder() {
        viewModel.filterVaults(vaults: vaults, folders: folders)
        folder.folderName = folderName
        
        dismiss()
    }

    func deleteFolder() {
        onDelete(folder)
        dismiss()
    }
}


#Preview {
    EditFolderScreen(
        folder: Folder.example,
        onDelete: { _ in }
    )
    .environmentObject(HomeViewModel())
}
