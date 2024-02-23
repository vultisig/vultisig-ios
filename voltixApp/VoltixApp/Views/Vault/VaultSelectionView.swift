//
//  VaultSelection.swift
//  VoltixApp
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers


struct VaultSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: ApplicationState
    @Query var vaults: [Vault]
    @Binding var presentationStack: [CurrentScreen]
    @State private var showingDeleteAlert = false
    @State private var itemToDelete: Vault? = nil
    @State private var showingExporter = false
    @State private var vaultToExport: Vault? = nil
    
    var body: some View {
        List(selection: $appState.currentVault) {
            ForEach(vaults, id: \.self) { vault in
                VStack {
                    HStack {
                        NavigationLink(destination: ListVaultAssetView(presentationStack: $presentationStack),
                                       label: {
                            Text(vault.name)
                                .swipeActions {
                                    Button("Delete", role: .destructive) {
                                        self.itemToDelete = vault
                                        showingDeleteAlert = true
                                    }
                                }
                        })
                        Image(systemName: "pencil").onTapGesture {
                            print("pencil clicked")
                        }
                    }
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("backup")
                        Spacer()
                    }.onTapGesture {
                        vaultToExport = vault
                        self.showingExporter = true
                    }
                }
            }
        }
        .fileExporter(isPresented: $showingExporter,
                      document: VoltixDocument(vault: vaultToExport),
                      contentType: .data,
                      defaultFilename: "\(vaultToExport?.name ?? "vault").dat",
                      onCompletion: { result in
            switch result {
            case .failure(let err):
                print("fail to export,error:\(err.localizedDescription)")
            case .success(let url):
                print("exported to \(url)")
            }
        })
        .confirmationDialog(Text("Delete Vault"), isPresented: $showingDeleteAlert, titleVisibility: .automatic) {
            Button("Confirm Delete \(itemToDelete?.name ?? "Vault")", role: .destructive) {
                withAnimation {
                    if let itemToDelete {
                        deleteVault(vault: itemToDelete)
                    }
                }
            }
        } message: {
            Text("Are you sure want to delete selected vault? \n Operation is not reversable")
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("New vault", systemImage: "plus") {
                    let vault = Vault(name: "Vault #\(vaults.count + 1)")
                    appState.creatingVault = vault
                    self.presentationStack.append(.newWalletInstructions)
                }
            }
        }.navigationBarBackButtonHidden()
    }
    
    func deleteVault(vault: Vault) {
        modelContext.delete(vault)
        do {
            try modelContext.save()
        } catch {
            print("Error:\(error)")
        }
    }
}
