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
        ScrollView {
            ForEach(vaults, id: \.self) { vault in
                NavigationLink {
                    VaultAssetsView(presentationStack: $presentationStack)
                        .onAppear(){
                            appState.currentVault = vault
                        }
                } label: {
                    HStack{
                        Text("\(vault.name)")
                        Spacer()
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("CHOOSE A VAULT")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("New vault", systemImage: "plus") {
                    let vault = Vault(name: "Vault #\(vaults.count + 1)")
                    appState.creatingVault = vault
                    self.presentationStack.append(.peerDiscovery)
                }
                Button("Join keygen", systemImage: "circle.hexagonpath") {
                    let vault = Vault(name: "Vault #\(vaults.count + 1)")
                    appState.creatingVault = vault
                    self.presentationStack.append(.joinKeygen)
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

#Preview("VaultSelection") {
    ModelContainerPreview(Vault.sampleVaults) {
        VaultSelectionView(presentationStack: .constant([]))
    }
}
