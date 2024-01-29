//
//  SendVerifyView.swift
//  VoltixApp
//

import SwiftUI

struct SendVerifyView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("Send verify view")
    }
}

#Preview {
    SendVerifyView(presentationStack: .constant([]))
}
