//
//  VaultSelection.swift
//  VoltixApp
//

import SwiftData
import SwiftUI

struct VaultSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: ApplicationState
    @Query var vaults: [Vault]
    @Binding var presentationStack: [CurrentScreen]
    @State private var showingDeleteAlert = false
    @State private var itemToDelete: Vault? = nil
    var body: some View {
        List(selection: $appState.currentVault) {
            ForEach(vaults) { vault in
                NavigationLink {
                    VaultAssetsView(presentationStack: $presentationStack, transactionDetailsViewModel: TransactionDetailsViewModel())
                } label: {
                    Text(vault.name)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                self.itemToDelete = vault
                                showingDeleteAlert = true
                            }
                        }
                }
            }
        }
        .confirmationDialog(Text("Delete Vault"), isPresented: $showingDeleteAlert, titleVisibility: .automatic) {
            Button("Delete", role: .destructive) {
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

private struct Item {
    var coinName: String
    var address: String
    var amount: String
    var coinAmount: String
}
