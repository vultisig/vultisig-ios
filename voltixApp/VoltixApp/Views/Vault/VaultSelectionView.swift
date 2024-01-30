//
//  VaultSelection.swift
//  VoltixApp
//
//  Created by Johnny Luo on 30/1/2024.
//

import SwiftUI
import SwiftData

struct VaultSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState:ApplicationState
    @Query var vaults:[Vault]
    @Binding var presentationStack: Array<CurrentScreen>
    var body: some View {
        List(selection: $appState.currentVault){
            ForEach(vaults){vault in
                Text(vault.name)
            }
        }
        .toolbar{
            Button(action: {
                self.presentationStack = [CurrentScreen.newWalletInstructions]
            }, label: {
                Label("New vault",systemImage: "plus")
            })
            
        }.navigationBarBackButtonHidden()
    }
}

#Preview("VaultSelection") {
    ModelContainerPreview(Vault.sampleVaults){ 
        VaultSelectionView(presentationStack: .constant([]))
    }
}

