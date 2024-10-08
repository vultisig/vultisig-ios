//
//  FolderDetailView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-04.
//

import SwiftUI
import SwiftData

struct FolderDetailView: View {
    @Binding var vaultFolder: VaultFolder
    @Binding var showVaultsList: Bool
    @ObservedObject var viewModel: HomeViewModel
    @Binding var folders: [VaultFolder]
    
    @State var isEditing = false
    @State var selectedVaults: [Vault] = []
    @State var remaningVaults: [Vault] = []
    
    @State var showAlert = false
    @State var alertTitle = ""
    @State var alertDescription = ""
    
    @Query var vaults: [Vault]
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .alert(isPresented: $showAlert) {
            alert
        }
        .onAppear {
            setData()
        }
        .onChange(of: vaultFolder.containedVaults) { oldValue, newValue in
            setData()
        }
    }
    
    var content: some View {
        ScrollView {
            selectedVaultsList
            
            if isEditing {
                remainingVaultsList
            }
        }
    }
    
    var navigationEditButton: some View {
        Button {
            withAnimation {
                isEditing.toggle()
            }
        } label: {
            if isEditing {
                doneLabel
            } else {
                editIcon
            }
        }
    }
    
    var selectedVaultsList: some View {
        VStack(spacing: 16) {
            ForEach(selectedVaults, id: \.self) { vault in
                FolderDetailSelectedVaultCell(vault: vault, isEditing: isEditing)
                    .onTapGesture {
                        handleVaultSelection(for: vault)
                    }
            }
        }
        .padding(.top, 30)
        .padding(.horizontal, 16)
    }
    
    var remainingVaultsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            vaultsTitle
            vaultsList
        }
        .padding(.horizontal, 16)
    }
    
    var vaultsTitle: some View {
        Text(NSLocalizedString("addVaultsToFolder", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratSemiBold)
            .padding(.top, 22)
    }
    
    var vaultsList: some View {
        ForEach(remaningVaults, id: \.self) { vault in
            FolderDetailRemainingVaultCell(vault: vault)
                .onTapGesture {
                    selectVault(vault)
                }
        }
    }
    
    var button: some View {
        Button {
            deleteFolder()
        } label: {
            label
        }
    }
    
    var label: some View {
        FilledButton(title: "deleteFolder", background: Color.miamiMarmalade)
            .padding(16)
            .edgesIgnoringSafeArea(.bottom)
            .frame(maxHeight: isEditing ? nil : 0)
            .clipped()
            .background(Color.backgroundBlue)
    }
    
    var editIcon: some View {
        Image(systemName: "square.and.pencil")
            .foregroundColor(Color.neutral0)
            .font(.body18MenloBold)
    }
    
    var doneLabel: some View {
        Text(NSLocalizedString("done", comment: ""))
            .foregroundColor(Color.neutral0)
            .font(.body18MenloBold)
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(alertTitle, comment: "")),
            message: Text(NSLocalizedString(alertDescription, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    func setData() {
        selectedVaults = []
        remaningVaults = []
        selectedVaults = vaultFolder.containedVaults
        remaningVaults = vaults.filter({ vault in
            !vaultFolder.containedVaults.contains(vault)
        })
    }
    
    private func selectVault(_ vault: Vault) {
        selectedVaults.append(vault)
        vaultFolder.containedVaults = selectedVaults
    }
    
    private func handleVaultSelection(for vault: Vault) {
        if isEditing {
            removeVault(vault)
        } else {
            handleSelection(for: vault)
        }
    }
    
    private func removeVault(_ vault: Vault) {
        let count = selectedVaults.count
        
        guard count > 1 else {
            alertTitle = "error"
            alertDescription = "folderNeedsOneVault"
            showAlert = true
            return
        }
        
        for index in 0..<count {
            if selectedVaults[index] == vault {
                selectedVaults.remove(at: index)
                return
            }
        }
        
        vaultFolder.containedVaults = selectedVaults
    }
    
    private func handleSelection(for vault: Vault) {
        viewModel.setSelectedVault(vault)
        showVaultsList = false
        dismiss()
    }
    
    private func deleteFolder() {
        for index in 0..<folders.count {
            if folders[index] == vaultFolder {
                folders.remove(at: index)
                dismiss()
                return
            }
        }
    }
}

#Preview {
    FolderDetailView(
        vaultFolder: .constant(VaultFolder.example),
        showVaultsList: .constant(false),
        viewModel: HomeViewModel(), 
        folders: .constant([])
    )
}
