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
    @State var detents: Set<PresentationDetent> = [.medium, .large]
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
        .presentationDetents(detents, selection: $detentSelection)
        .presentationCompactAdaptation(.none)
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
        .onChange(of: isEditing) { _, newValue in
            updateDetents(whileAnimation: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    if newValue {
                        detentSelection = .large
                    } else {
                        detentSelection = .medium
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    updateDetents(whileAnimation: false)
                }
            }
        }
        .customDetentsSheet(item: $folderToEdit) {
            EditFolderScreen(folder: $0, onDelete: onDelete)
        }
        .customDetentsSheet(isPresented: $showAddFolder) {
            AddFolderScreen()
        }
        .onAppear {
            updateDetents(whileAnimation: false)
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

private struct CustomDetentsSheetWithItem<Item: Identifiable & Equatable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    var sheetContent: (Item) -> SheetContent
    
    @State var itemInternal: Item? = nil
    
    func body(content: Content) -> some View {
        content
            .if(item != nil) {
                $0.sheet(item: $itemInternal) {
                    sheetContent($0)
                }
            }
            .onChange(of: item) { _, newValue in
                DispatchQueue.main.async {
                    itemInternal = newValue
                }
            }
            .onChange(of: itemInternal) { _, newValue in
                DispatchQueue.main.async {
                    item = newValue
                }
            }
    }
}

private struct CustomDetentsSheetWithBoolean<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var sheetContent: () -> SheetContent
    
    @State var isPresentedInternal: Bool = false
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresentedInternal) {
                sheetContent()
                    .onDisappear {
                        isPresented = false
                    }
            }
            .onChange(of: isPresented) { _, newValue in
                DispatchQueue.main.async {
                    isPresentedInternal = newValue
                }
            }
    }
}

extension View {
    func customDetentsSheet<Item: Identifiable & Equatable, SheetContent: View>(item: Binding<Item?>, content: @escaping (Item) -> SheetContent) -> some View {
        modifier(CustomDetentsSheetWithItem(item: item, sheetContent: content))
    }
    
    func customDetentsSheet<SheetContent: View>(isPresented: Binding<Bool>, content: @escaping () -> SheetContent) -> some View {
        modifier(CustomDetentsSheetWithBoolean(isPresented: isPresented, sheetContent: content))
    }
}


