//
//  SwapWaitingForPeersView.swift
//  VoltixApp
//

import SwiftUI

struct SwapWaitingForPeersView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("swap waiting for peers")
    }
}

#Preview {
    SwapWaitingForPeersView(presentationStack: .constant([]))
}
