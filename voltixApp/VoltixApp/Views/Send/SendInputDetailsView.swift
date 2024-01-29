//
//  SendInputDetailsView.swift
//  VoltixApp
//

import SwiftUI

struct SendInputDetailsView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("Send - input details view")
    }
}

#Preview {
    SendInputDetailsView(presentationStack: .constant([]))
}
