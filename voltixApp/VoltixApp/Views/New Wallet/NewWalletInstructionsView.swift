//
//  NewWalletInstructions.swift
//  VoltixApp
//

import SwiftData
import SwiftUI

struct NewWalletInstructions: View {
    @Binding var presentationStack: [CurrentScreen]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: ApplicationState
    @Query var vaults: [Vault]

    var body: some View {
        ScrollView {
            VStack {
                Text("YOU NEED THREE DEVICES.")
                    .fontWeight(.medium)
                    .lineSpacing(36)
                DeviceView(
                    number: "1",
                    description: "MAIN",
                    deviceImg: "Device1",
                    deviceDescription: "A MACBOOK"
                )
                Spacer()
                DeviceView(
                    number: "2",
                    description: "PAIR",
                    deviceImg: "Device2",
                    deviceDescription: "ANY"
                )
                Spacer()
                DeviceView(
                    number: "3",
                    description: "PAIR",
                    deviceImg: "Device3",
                    deviceDescription: "ANY"
                )
                WifiBar()
                HStack{
                    Button("JOIN KEYGEN") {
                        let vault = Vault(name: "Vault #\(vaults.count + 1)")
                        appState.creatingVault = vault
                        self.presentationStack.append(.joinKeygen)
                    }
                    Button("START KEYGEN") {
                        let vault = Vault(name: "Vault #\(vaults.count + 1)")
                        appState.creatingVault = vault
                        self.presentationStack.append(.peerDiscovery)
                    }
                }
            }
            .navigationTitle("SETUP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationButtons.questionMarkButton
                }
            }
        }
    }
}

#Preview {
    NewWalletInstructions(presentationStack: .constant([]))
}
