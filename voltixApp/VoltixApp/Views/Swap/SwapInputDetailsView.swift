//
//  SwapInputDetailsView.swift
//  VoltixApp
//

import SwiftUI

struct SwapInputDetailsView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("Swap input details view")
    }
}

#Preview {
    SwapInputDetailsView(presentationStack: .constant([]))
}
