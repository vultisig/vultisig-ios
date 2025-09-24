//
//  AddFolderScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI
import SwiftData

struct AddFolderScreen: View {
    @Query var vaults: [Vault]
    @Query var folders: [Folder]
    
    @State var filteredVaults: [Vault] = []
    
    @StateObject var folderViewModel = CreateFolderViewModel()
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: HomeViewModel
    
    var body: some View {
        view
            .padding(.top, 24)
            .padding(.horizontal, 16)
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.colors.bgPrimary)
            .onLoad(perform: setData)
            .alert(isPresented: $folderViewModel.showAlert) {
                alert
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
                    text: $folderViewModel.name,
                    label: "folderName".localized,
                    placeholder: "typeHere".localized,
                )
                .plainListItem()
                
                sectionHeader(title: "selectVaults".localized)
                vaultsList
            }
            .listSectionSpacing(0)
            .listStyle(.plain)
            .buttonStyle(.borderless)
            .scrollContentBackground(.hidden)
            .background(Theme.colors.bgPrimary)
        }
    }
    
    var vaultsList: some View {
        ForEach(filteredVaults, id: \.self) { vault in
            AddFolderVaultCellView(
                vault: vault,
                isSelected: folderViewModel.selectedVaults.contains(vault),
                onSelection: {
                    handleSelection(vault: vault, isSelected: $0)
                }
            )
            .plainListItem()
        }
    }
    
    var saveButton: some View {
        PrimaryButton(title: "save") {
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
        .disabled(folderViewModel.saveButtonDisabled)
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
                BottomSheetButton(icon: "x", type: .secondary) {
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    
    private func setData() {
        viewModel.filterVaults(vaults: vaults, folders: folders)
        self.filteredVaults = viewModel.filteredVaults
    }

    private func saveFolder() {
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
            dismiss()
        }
    }
    
    private func handleSelection(vault: Vault, isSelected: Bool) {
        if isSelected {
            folderViewModel.selectedVaults.append(vault)
        } else {
            removeVault(vault)
        }
    }
    
    private func removeVault(_ vault: Vault) {
        for index in 0..<folderViewModel.selectedVaults.count {
            if areVaultsSame(folderViewModel.selectedVaults[index], vault) {
                folderViewModel.selectedVaults.remove(at: index)
                return
            }
        }
    }
    
    private func areVaultsSame(_ selectedVault: Vault, _ vault: Vault) -> Bool {
        selectedVault.name == vault.name && selectedVault.pubKeyECDSA == vault.pubKeyECDSA && selectedVault.pubKeyEdDSA == vault.pubKeyEdDSA
    }
}

struct AddFolderVaultCellView: View {
    let vault: Vault
    let isSelected: Bool
    var onSelection: (Bool) -> Void
    @State var isSelectedInternal: Bool = false
    
    var body: some View {
        HStack {
            VaultCellMainView(vault: vault)
                .opacity(isSelectedInternal ? 1 : 0.5)
                .animation(.interpolatingSpring, value: isSelectedInternal)
            Spacer()
            Toggle("", isOn: $isSelectedInternal)
                .labelsHidden()
                .scaleEffect(0.8)
                .tint(Theme.colors.primaryAccent4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgSecondary)
        .onLoad {
            isSelectedInternal = isSelected
        }
        .onChange(of: isSelectedInternal) {
            guard isSelectedInternal != isSelected else {
                return
            }
            
            // Wait for toggle animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onSelection(isSelectedInternal)
            }
        }
    }
}

#Preview {
    AddFolderScreen()
    .environmentObject(HomeViewModel())
}
