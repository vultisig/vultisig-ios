//
//  SwapPeerDiscoveryView.swift
//  VoltixApp
//

import SwiftUI

struct SwapPeerDiscoveryView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("swap p2p discovery")
    }
}

#Preview {
    SwapPeerDiscoveryView(presentationStack: .constant([]))
}
