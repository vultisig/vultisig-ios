//
//  VaultManagementSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftData
import SwiftUI

struct VaultManagementSheet: View {
    @Query(sort: \Vault.order, order: .forward) var vaults: [Vault]
    @Query(sort: \Folder.order, order: .forward) var folders: [Folder]
        
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var homeViewModel: HomeViewModel
    @StateObject var viewModel = VaultSelectorViewModel()
        
    @State var isEditing: Bool = false
    @State var selectedFolder: Folder?
    @State var folderToEdit: Folder?
    @State var showAddFolder: Bool = false
    @State var detents: [PresentationDetent] = [.medium, .large]
    @State var detentSelection = PresentationDetent.medium
    
    var onAddVault: () -> Void
    var onSelectVault: (Vault) -> Void
    
    var body: some View {
        VStack {
            Group {
                if let selectedFolder {
                    FolderDetailView(
                        folder: selectedFolder,
                        onSelectVault: onSelectVault,
                        onEditFolder: onEditFolder,
                        onBack: onFolderBack
                    )
                    .transition(.move(edge: .trailing))
                } else {
                    VaultListView(
                        isEditing: $isEditing,
                        onAddVault: onAddVault,
                        onSelectVault: onSelectVault
                    ) {
                        self.selectedFolder = $0
                    } onAddFolder: {
                        showAddFolder = true
                    }
                    .transition(.move(edge: .leading))
                }
            }
            .animation(.easeInOut, value: selectedFolder)
        }
        .padding(.top, 24)
        .padding(.horizontal, 16)
        .presentationDragIndicator(.visible)
        .presentationDetents(Set(detents), selection: $detentSelection)
        .presentationCompactAdaptation(.none)
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
        .onChange(of: isEditing) { _, isEditing in
            updateDetents(isEditing: isEditing)
        }
        .detentsAwareSheet(item: $folderToEdit) {
            EditFolderScreen(folder: $0, onDelete: onDelete)
        }
        .detentsAwareSheet(isPresented: $showAddFolder) {
            AddFolderScreen()
        }
        .onLoad {
            updateDetents(whileAnimation: false)
        }
    }
}

private extension VaultManagementSheet {
    // This is to support detents animation
    func updateDetents(isEditing: Bool) {
        updateDetents(whileAnimation: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            detentSelection = detents[0]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                updateDetents(whileAnimation: false)
            }
        }
    }
    func updateDetents(whileAnimation: Bool) {
        let whileAnimationDetents: [PresentationDetent] = whileAnimation ? [.large, .medium] : []
        let stateDetents: [PresentationDetent]
        
        if isEditing {
            stateDetents = whileAnimationDetents
            self.detents = stateDetents + whileAnimationDetents
            return
        }
        
        let elementsCount = vaults.count + folders.count
        switch elementsCount {
        case 1:
            stateDetents = [.height(214)] + whileAnimationDetents
            break
        case 2:
            stateDetents = [.height(278)] + whileAnimationDetents
            break
        case 3:
            stateDetents = [.medium] + whileAnimationDetents
            break
        default:
            stateDetents = [.medium, .large] + whileAnimationDetents
            break
        }
        
        self.detents = stateDetents + whileAnimationDetents
    }
    
    func onEditFolder() {
        folderToEdit = selectedFolder
    }
    
    func onFolderBack() {
        selectedFolder = nil
    }
    
    func onDelete(_ folder: Folder) {
        selectedFolder = nil
        modelContext.delete(folder)
        do {
            try modelContext.save()
        } catch {
            print("Error while deleting folder: \(error)")
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
               VaultManagementSheet(
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
