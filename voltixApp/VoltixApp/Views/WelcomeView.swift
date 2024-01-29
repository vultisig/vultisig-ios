//
//  WelcomeView.swift
//  VoltixApp
//

import SwiftUI

struct WelcomeView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        VStack {
            Text("Welcome Screen")
            Button("Continue >") {
                presentationStack.append(.startScreen)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    WelcomeView(presentationStack: .constant([]))
}
