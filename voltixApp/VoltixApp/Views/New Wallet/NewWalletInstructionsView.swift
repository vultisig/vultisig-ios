//
//  NewWalletInstructions.swift
//  VoltixApp
//

import SwiftUI

struct NewWalletInstructions: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("New Wallet Instructions")
        Button("Continue") {
            presentationStack.append(.peerDiscovery)
        }
    }
}

#Preview {
    NewWalletInstructions(presentationStack: .constant([]))
}
