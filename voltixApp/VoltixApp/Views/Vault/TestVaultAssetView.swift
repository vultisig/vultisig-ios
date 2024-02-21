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
                Button("send", systemImage: "paperplane") {
                    if let coin = appState.currentVault?.coins[0] {
                        self.presentationStack.append(CurrentScreen.keysignTest(coin))
                    }
                }
            }
        }
        .onAppear {
            if let vault = appState.currentVault {
                let result = BitcoinHelper.getBitcoin(hexPubKey: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
                switch result {
                    case .success(let btc):
                        print("btc: \(btc)")
                    case .failure(let error):
                        print("error: \(error)")
                }
                // TODO: remove the following few lines , just for development
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
