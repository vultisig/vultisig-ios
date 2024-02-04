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
            Text("ECDSA PubKey: \(vault.pubKeyECDSA)")
            Text("EdDSA PubKey: \(vault.pubKeyEdDSA)")
            
            Button("Backup local share"){
                // TODO , genereate a QRCode and let user to print it out
            }
           
            Button("Done >") {
                appState.currentVault = vault
                presentationStack.removeAll()  // Show Vault
            }
            
        }.onAppear(){
            for item in vault.keyshares {
                print("pubkey:\(item.pubkey) , share:\(item.keyshare)")
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    FinishedTSSKeygenView(presentationStack: .constant([]), vault: Vault(name: "my vault"))
}
