//
//  StartView.swift
//  VoltixApp
//

import SwiftUI

struct StartView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("Start View")
        Button("Import Wallet >") {
            presentationStack.append(.importWallet)
        }
        Button("New Wallet >") {
            presentationStack.append(.newWalletInstructions)
        }
    }
}

#Preview {
    StartView(presentationStack: .constant([]))
}
