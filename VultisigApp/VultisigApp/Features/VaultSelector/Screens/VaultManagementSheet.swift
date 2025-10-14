//
//  VaultManagementSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftData
import SwiftUI

fileprivate enum VaultSheetType: Equatable {
    case main
    case editFolder
    case addFolder
}

struct VaultManagementSheet: View {
    @Query(sort: \Vault.order, order: .forward) var vaults: [Vault]
    @Query(sort: \Folder.order, order: .forward) var folders: [Folder]
    
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State var isEditing: Bool = false
    @State var selectedFolder: Folder?
    @State var folderToEdit: Folder?
    @State var showAddFolder: Bool = false
    @State var detents: [PresentationDetent] = [.medium, .large]
    @State var detentSelection = PresentationDetent.medium
    
    @State private var sheetType = VaultSheetType.main
    @State private var shouldUseMoveTransition = true
    
    var onAddVault: () -> Void
    var onSelectVault: (Vault) -> Void
    
    var body: some View {
        VStack {
            Group {
                switch sheetType {
                case .main:
                    mainSheetView
                case .editFolder:
                    EditFolderScreen(folder: folderToEdit!, onDelete: onDelete) {
                        updateSheet(.main)
                    }
                case .addFolder:
                    AddFolderScreen {
                        updateSheet(.main)
                    }
                }
            }
            .transition(.opacity)
        }
#if os(iOS)
        .presentationDragIndicator(.visible)
        .presentationDetents(Set(detents), selection: $detentSelection)
        .presentationCompactAdaptation(.none)
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
        .onChange(of: isEditing) { _, isEditing in
            updateDetents(isEditing: isEditing)
        }
        .onChange(of: sheetType) { _, _ in
            updateDetents(isEditing: isEditing)
        }
        .onLoad {
            updateDetents(whileAnimation: false)
        }
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.colors.bgPrimary)
#endif
    }
    
    var mainSheetView: some View {
        ZStack {
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
                    ) { selectedFolder in
                        shouldUseMoveTransition = true
                        withAnimation(.interpolatingSpring) {
                            self.selectedFolder = selectedFolder
                        }
                    } onAddFolder: {
                        updateSheet(.addFolder)
                    }
                    .transition(.move(edge: .leading))
                }
            }
        }
    }
}

private extension VaultManagementSheet {
    // This is to support detents animation
    func updateDetents(isEditing: Bool) {
        updateDetents(whileAnimation: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            detentSelection = isEditing ? .large : detents[safe: 0] ?? .medium
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                updateDetents(whileAnimation: false)
            }
        }
    }
    func updateDetents(whileAnimation: Bool) {
        let whileAnimationDetents: [PresentationDetent] = whileAnimation ? [.large, .medium] : []
        let stateDetents: [PresentationDetent]
        
        if isEditing || sheetType != .main {
            self.detents = [.large] + whileAnimationDetents
            return
        }
        
        let vaults = homeViewModel.getFilteredVaults(vaults: vaults, folders: folders)
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
        updateSheet(.editFolder)
    }
    
    func onFolderBack() {
        shouldUseMoveTransition = true
        withAnimation(.interpolatingSpring) {
            selectedFolder = nil
        }
    }
    
    func onDelete(_ folder: Folder) {
        selectedFolder = nil
        modelContext.delete(folder)
        updateSheet(.main)
        do {
            try modelContext.save()
        } catch {
            print("Error while deleting folder: \(error)")
        }
    }
    
    func updateSheet(_ sheetType: VaultSheetType) {
        shouldUseMoveTransition = false
        DispatchQueue.main.async {
            withAnimation(.interpolatingSpring) {
                self.sheetType = sheetType
            }
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
            .crossPlatformSheet(isPresented: $isPresented) {
                VaultManagementSheet(
                    onAddVault: {},
                    onSelectVault: { _ in },
                )
            }
            .background(Theme.colors.bgPrimary)
        }
    }
    
    return PreviewContainer()
        .environmentObject(HomeViewModel())
}
