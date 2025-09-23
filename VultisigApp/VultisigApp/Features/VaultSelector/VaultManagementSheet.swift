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
    @State var detents: Set<PresentationDetent> = [.medium]
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
                    }
                    .transition(.move(edge: .leading))
                }
            }
            .animation(.easeInOut, value: selectedFolder)
        }
        .padding(.top, 24)
        .padding(.horizontal, 16)
        .presentationDragIndicator(.visible)
        .presentationDetents(detents, selection: $detentSelection)
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
        .onChange(of: isEditing) { _, newValue in
            updateDetents(whileAnimation: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if newValue {
                        detentSelection = .large
                    } else {
                        detentSelection = .medium
                    }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    updateDetents(whileAnimation: false)
                }
            }
        }
        .onAppear {
            updateDetents(whileAnimation: false)
        }
        .sheet(item: $folderToEdit) {
            EditFolderScreen(folder: $0)
        }
    }
    
    func updateDetents(whileAnimation: Bool) {
        let whileAnimationDetents: [PresentationDetent] = whileAnimation ? [.medium, .large] : []
        if isEditing {
            detents = [.medium, .large]
            return
        }
        
        if vaults.count >= 8 || folders.count >= 4 {
            detents = [.medium, .large]
            return
        }
        
        switch vaults.count {
        case 1:
            detents = Set([.height(214)] + whileAnimationDetents)
            return
        case 2:
            detents = Set([.height(278)] + whileAnimationDetents)
            return
        default:
            detents = Set([.medium] + whileAnimationDetents)
            return
        }
    }
    
    func onEditFolder() {
        folderToEdit = selectedFolder
    }
    
    func onFolderBack() {
        selectedFolder = nil
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

