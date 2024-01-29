//
//  VaultView.swift
//  VoltixApp
//

import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: Array<CurrentScreen>
        
    var body: some View {
        Text("VaultAssetsView")
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
