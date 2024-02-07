//
//  KeysignTestView.swift
//  VoltixApp

import SwiftUI

struct KeysignTestView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @EnvironmentObject var appState:ApplicationState
    @State private var keysignMessage = "Stuff to sign"
    @State private var chains = [Chain.THORChain,Chain.Solana]
    @State private var currentChain: Chain? = nil
    
    var body: some View {
        VStack{
            List(chains,id: \.self,selection: $currentChain){c in
                Text(c.name)
            }
            TextField("keysign message",text: $keysignMessage)
            Spacer()
            Button("Sign it",systemImage: "person.2.badge.key.fill"){
                self.presentationStack.append(.KeysignDiscovery(keysignMessage, currentChain ?? Chain.THORChain))
            }
        }
    }
}

#Preview {
    KeysignTestView(presentationStack: .constant([]))
}
