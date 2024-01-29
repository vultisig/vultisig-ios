//
//  VaultAssetDetailView.swift
//  VoltixApp
//

import SwiftUI

struct VaultAssetDetailView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    let type: AssetType
    
    var body: some View {
        Text("Specific Vault Asset - \(type.chainName)")
        Button("Swap") {
            
        }
        Button("Send") {
            
        }
    }
}

#Preview {
    VaultAssetDetailView(presentationStack: .constant([]), type: .bitcoin)
}
