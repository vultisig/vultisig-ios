//
//  SendWaitingForPeersView.swift
//  VoltixApp
//

import SwiftUI

struct SendWaitingForPeersView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("sendWaitingForPeers")
    }
}

#Preview {
    SendWaitingForPeersView(presentationStack: .constant([]))
}
