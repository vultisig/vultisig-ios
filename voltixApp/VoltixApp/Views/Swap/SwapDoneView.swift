//
//  SwapDoneView.swift
//  VoltixApp
//

import SwiftUI

struct SwapDoneView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("swap done")
    }
}

#Preview {
    SwapDoneView(presentationStack: .constant([]))
}
