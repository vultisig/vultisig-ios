//
//  FinishedTSSKeygenView.swift
//  VoltixApp
//

import SwiftUI

struct FinishedTSSKeygenView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var checkbox1 = false
    @State private var checkbox2 = false
    @State private var checkbox3 = false
    
    var body: some View {
        VStack {
            Text("Finished TSS Keygen")
            Text("BTC Address...")
            Text("ETH Address...")
            HStack {
                Text("I've saved a backup of the vault")
                Button(action: { checkbox1 = !checkbox1 }) {
                    if checkbox1 {
                        Image(systemName: "checkmark.circle")
                    } else {
                        Image(systemName: "circle")
                    }
                }
            }
            HStack {
                Text("Nobody but me can access the backup")
                Button(action: { checkbox2 = !checkbox2 }) {
                    if checkbox2 {
                        Image(systemName: "checkmark.circle")
                    } else {
                        Image(systemName: "circle")
                    }
                }
            }
            HStack {
                Text("It's not located with the other backups")
                Button(action: { checkbox3 = !checkbox3 }) {
                    if checkbox3 {
                        Image(systemName: "checkmark.circle")
                    } else {
                        Image(systemName: "circle")
                    }
                }
            }
            Button("Finish >") {
                presentationStack.removeAll()  // Show Vault
            }
            .disabled(!checkbox1 || !checkbox2 || !checkbox3)
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    FinishedTSSKeygenView(presentationStack: .constant([]))
}
