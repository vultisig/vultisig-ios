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
    
    @State var isEditing = false
    @State var selectedVaults: [Vault] = []
    @State var remaningVaults: [Vault] = []
    
    @Query var vaults: [Vault]
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Background()
            view
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
        for index in 0..<selectedVaults.count {
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
}

#Preview {
    FolderDetailView(
        vaultFolder: .constant(VaultFolder.example),
        showVaultsList: .constant(false),
        viewModel: HomeViewModel()
    )
}
