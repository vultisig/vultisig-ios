//
//  VaultSelection.swift
//  VoltixApp
//

import SwiftData
import SwiftUI

struct VaultSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: ApplicationState
    @ObservedObject var unspentOutputsViewModel: UnspentOutputsViewModel
    @Query var vaults: [Vault]
    @Binding var presentationStack: [CurrentScreen]
    @State private var showingDeleteAlert = false
    @State private var itemToDelete: Vault? = nil
    var body: some View {
        VStack {
            LargeHeaderView( 
                rightIcon: "Refresh",
                leftIcon: "Menu",
                head: "VAULT",
                leftAction: {
                    if !self.presentationStack.isEmpty {
                        self.presentationStack.removeLast()
                    }
                },
                rightAction: {
                    // open help modal
                },
                back: false
            )
            VStack {
                ForEach(items.indices, id: \.self) { index in
                    VaultItem(
                        coinName: items[index].coinName,
                        amount: items[index].amount,
                        coinAmount: items[index].coinAmount,
                        address: items[index].address,
                        isRadio: !Utils.isIOS(),
                        showButtons: !Utils.isIOS(),
                        onClick: {
                            VaultAssetsView(presentationStack: $presentationStack, appState: _appState, unspentOutputsViewModel:unspentOutputsViewModel , transactionDetailsViewModel: TransactionDetailsViewModel()).onAppear {
                                appState.currentVault = Vault(name: "test", signers:["A","B","C"],  pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey",keyshares: [KeyShare](), localPartyID: "first")
                            }
                        }
                    )
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .frame(width: .infinity)
        }
        .onAppear {
            self.appState.currentVault = Vault(name: "test", signers:["A","B","C"],  pubKeyECDSA: "ECDSA PubKey", pubKeyEdDSA: "EdDSA PubKey",keyshares: [KeyShare](), localPartyID: "first")
        }
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(.white)
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
