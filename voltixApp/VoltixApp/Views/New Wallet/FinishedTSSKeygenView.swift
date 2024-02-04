//
//  FinishedTSSKeygenView.swift
//  VoltixApp
//

import SwiftUI

struct FinishedTSSKeygenView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @Environment(\.modelContext) private var context
    @EnvironmentObject var appState: ApplicationState
    @ObservedObject var vault: Vault
    
    @State private var checkbox1 = false
    @State private var checkbox2 = false
    @State private var checkbox3 = false
    
    
    var body: some View {
        VStack {
            Text("vault: \(vault.name)")
            Button("Backup local share"){
                
            }
           
            Button("Done >") {
                appState.currentVault = vault
                presentationStack.removeAll()  // Show Vault
            }
            
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    FinishedTSSKeygenView(presentationStack: .constant([]), vault: Vault(name: "my vault"))
}
