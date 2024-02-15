import OSLog
import SwiftData
import SwiftUI
import CoreData


private let logger = Logger(subsystem: "peers-discory", category: "communication")
struct StartView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState
    
    @Environment(\.modelContext) private var modelContext
    @State private var vaults: [Vault] = []
    
    private func loadVaults() {
        do {
            // Assuming FetchDescriptor allows for an empty initializer to fetch all entities
            let fetchDescriptor = FetchDescriptor<Vault>()
            self.vaults = try modelContext.fetch(fetchDescriptor)
            for vault in vaults {
                print("id: \(vault.id) \n name:\(vault.name) \n pubKeyECDSA: \(vault.pubKeyECDSA) \n pubKeyEdDSA: \(vault.pubKeyEdDSA) \n\n")
            }
            
        } catch {
            // Handle errors, perhaps showing an alert to the user
            print("Error fetching vaults: \(error)")
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView { // To meke the list appear we need to remove the ScrollView
                VStack {
                    
                    //                    List {
                    //                        ForEach(vaults, id: \.name) { vault in
                    //                            VStack(alignment: .leading) {
                    //                                //Text("ID: \(vault.id)")
                    //                                Text("Name: \(vault.name)")
                    //                                Text("Public Key ECDSA: \(vault.pubKeyECDSA)")
                    //                                Text("Public Key EdDSA: \(vault.pubKeyEdDSA)")
                    //                                Divider()
                    //                            }
                    //                        }
                    //                    }
                    
                    
                    
                    Spacer()
                    // New Vault Button and Text
                    VStack { // Increase spacing to ensure separation
                        LargeButton(
                            content: "NEW",
                            onClick: {
                                self.presentationStack.append(.newWalletInstructions)
                            }
                        )
                        Text("CREATE A NEW VAULT")
                    }
                    
                    Spacer()
                    // Import Vault Button and Text
                    VStack { // Increase spacing to ensure separation
                        LargeButton(
                            content: "IMPORT",
                            onClick: {
                                self.presentationStack.append(.importWallet)
                            }
                        )
                        
                        Text("IMPORT AN EXISTING VAULT")
                    }
                    
                }.onAppear {
                    loadVaults()
                }
            }
            .frame(width: geometry.size.width)
            .navigationTitle("START")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationButtons.questionMarkButton
                }
            }
        }
    }
}

// Preview
struct StartView_Previews: PreviewProvider {
    static var previews: some View {
        StartView(presentationStack: .constant([]))
    }
}
