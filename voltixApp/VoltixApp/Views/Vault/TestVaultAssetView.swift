//
//  TestVaultAssetView.swift
//  VoltixApp
//

import SwiftUI

struct TestVaultAssetView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    @State private var showingCoinList = false
    var body: some View {
        List {
            ForEach(appState.currentVault?.coins ?? [Coin](), id: \.self) {
                VaultItem(presentationStack: $presentationStack, coinName: $0.chain.name, usdAmount: "0", showAmount: true, address: $0.address, isRadio: true, radioIcon: "circle", showButtons: true)
            }
        }
        .navigationTitle(appState.currentVault?.name ?? "Vault")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCoinList) {
            AssetsList()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("add coins", systemImage: "plus") {
                    showingCoinList = true
                }
                NavigationButtons.refreshButton(action: {})
            }
        }
        .onAppear {
            if let vault = appState.currentVault {
                for keyshare in vault.keyshares {
                    if keyshare.pubkey == vault.pubKeyECDSA {
                        print("keyshare for \(vault.pubKeyECDSA): \(Utils.stringToHex(keyshare.keyshare))")
                    }
                }
            }
        }
    }
}

#Preview {
    TestVaultAssetView(presentationStack: .constant([]))
}
