//
//  SendWaitingForPeersView.swift
//  VoltixApp
//

import SwiftUI

struct SendWaitingForPeersView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        VStack{
            Text("sendWaitingForPeers")
        }.navigationTitle("SEND")
            .modifier(InlineNavigationBarTitleModifier())
            .toolbar {
              #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                  NavigationButtons.backButton(presentationStack: $presentationStack)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                  NavigationButtons.questionMarkButton
                }
              #else
                ToolbarItem {
                  NavigationButtons.backButton(presentationStack: $presentationStack)
                }
                ToolbarItem {
                  NavigationButtons.questionMarkButton
                }
              #endif
            }
    }
}

#Preview {
    SendWaitingForPeersView(presentationStack: .constant([]))
}
