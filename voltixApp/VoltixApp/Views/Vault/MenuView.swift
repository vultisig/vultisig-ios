//
//  MenuView.swift
//  VoltixApp
//

import SwiftUI

struct MenuView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        Text("Menu View")
    }
}

#Preview {
    MenuView(presentationStack: .constant([]))
}
