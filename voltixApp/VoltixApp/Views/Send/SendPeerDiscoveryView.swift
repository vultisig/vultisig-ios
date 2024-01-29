//
//  SendPeerDiscoveryView.swift
//  VoltixApp
//

import SwiftUI

struct SendPeerDiscoveryView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("Send P2p discovery")
    }
}

#Preview {
    SendPeerDiscoveryView(presentationStack: .constant([]))
}
