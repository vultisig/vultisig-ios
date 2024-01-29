//
//  SwapVerifyView.swift
//  VoltixApp
//

import SwiftUI

struct SwapVerifyView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("swap verify screen")
    }
}

#Preview {
    SwapVerifyView(presentationStack: .constant([]))
}
