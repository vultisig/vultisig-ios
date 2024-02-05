//
//  NewWalletInstructions.swift
//  VoltixApp
//

import SwiftUI

struct NewWalletInstructions: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State  var vaultName:String
    var body: some View {
        VStack{
            Text("New Vault").font(.largeTitle)
            VStack(alignment:.leading){
                Text("Enter new vault name").font(.title3)
                TextField("New vault name",text: $vaultName).textFieldStyle(.roundedBorder)
            }.padding(.top,20)
            Spacer()
            Button("create new vault",systemImage: "person.3.fill") {
                presentationStack.append(.peerDiscovery)
            }.disabled(!vaultName.isEmpty)
        }
    }
}

#Preview {
    NewWalletInstructions(presentationStack: .constant([]),vaultName: "")
}
