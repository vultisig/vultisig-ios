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
    var onClose: () -> Void

    @Query var folders: [Folder]
    @Query var vaults: [Vault]

    @State var folderName: String = ""
    @State var disableSelection: Bool = false
    @StateObject var folderViewModel = FolderDetailViewModel()

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: HomeViewModel
    @EnvironmentObject var appViewModel: AppViewModel

    var saveButtonDisabled: Bool {
        folderName.isEmpty || folderViewModel.selectedVaults.count == 0
    }

    var body: some View {
        view
            .padding(.top, 24)
            .padding(.bottom, isIPadOS ? 24 : 0)
            .padding(.horizontal, 16)
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
            CommonTextField(
                text: $folderName,
                label: "folderName".localized,
                placeholder: "enterVaultName".localized,
            )
            List {
                CommonListHeaderView(title: "activeVaults".localized)
                selectedVaultsList
                CommonListHeaderView(title: "available".localized)
                    .showIf(!folderViewModel.remainingVaults.isEmpty)
                vaultsList
            }
            .listStyle(.plain)
            .buttonStyle(.borderless)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(Theme.colors.bgPrimary)
            .safeAreaInset(edge: .bottom, content: { Spacer().frame(height: 100) })
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
                isSelected: appViewModel.selectedVault == vault,
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
                isSelected: appViewModel.selectedVault == vault,
                onSelection: { addVault(vault) }
            )
            .plainListItem()
        }
    }

    var saveButton: some View {
        ListBottomSection {
            PrimaryButton(title: "saveChanges") {
                saveFolder()
            }
            .disabled(saveButtonDisabled)
        }
    }

    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(folderViewModel.alertTitle, comment: "")),
            message: Text(NSLocalizedString(folderViewModel.alertDescription, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }

    var header: some View {
        HStack {
            HStack {}
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("editFolder".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title3)
            HStack {
                ToolbarButton(image: "trash", type: .destructive) {
                    deleteFolder()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private extension EditFolderScreen {
    func setData() {
        viewModel.filterVaults(vaults: vaults, folders: folders)
        folderViewModel.setData(
            vaults: vaults,
            vaultFolder: folder,
            filteredVaults: viewModel.filteredVaults
        )
        setupFolder()
        updateSelection()
    }

    func move(from: IndexSet, to: Int) {
        var s = folderViewModel.selectedVaults.sorted(by: { $0.order < $1.order })
        s.move(fromOffsets: from, toOffset: to)
        for (index, item) in s.enumerated() {
            item.order = index
        }
        try? self.modelContext.save()
    }

    func addVault(_ vault: Vault) {
        folderViewModel.addVault(vault: vault)
        updateFolder()
    }

    func removeVault(_ vault: Vault) {
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

    func setupFolder() {
        folderName = folder.folderName
    }

    func saveFolder() {
        viewModel.filterVaults(vaults: vaults, folders: folders)
        folder.folderName = folderName

        onClose()
    }

    func deleteFolder() {
        onDelete(folder)
        onClose()
    }
}

#Preview {
    EditFolderScreen(
        folder: Folder.example,
        onDelete: { _ in },
        onClose: {}
    )
    .environmentObject(HomeViewModel())
    .environmentObject(AppViewModel())
}
