//
//  VaultView.swift
//  VoltixApp
//

import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @EnvironmentObject var appState:ApplicationState
        
    var body: some View {
        Text("Vault \(appState.currentVault?.name ?? "") Assets View")
        List(AssetType.allCases, id: \.self) { asset in
            Button(asset.chainName) {
                presentationStack.append(.vaultDetailAsset(asset))
            }
        }
    }
}

#Preview {
    VaultAssetsView(presentationStack: .constant([]))
}
