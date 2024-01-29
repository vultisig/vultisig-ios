//
//  ImportWallet.swift
//  VoltixApp
//

import SwiftUI

struct ImportWalletView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State var vaultShare = ""
    
    var body: some View {
        Text("Import Wallet")
        TextField("Paste Vault Share", text: $vaultShare)
        Button("Continue") {
            // TODO: Process data, validate, save
            presentationStack = []  // Vault Assets List
        }
    }
}

#Preview {
    ImportWalletView(presentationStack: .constant([]))
}
