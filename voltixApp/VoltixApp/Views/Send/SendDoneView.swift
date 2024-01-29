//
//  SendDoneView.swift
//  VoltixApp
//

import SwiftUI

struct SendDoneView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("Send done")
    }
}

#Preview {
    SendDoneView(presentationStack: .constant([]))
}
