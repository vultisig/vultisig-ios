import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct VaultSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: ApplicationState
    @Query var vaults: [Vault]
    @Binding var presentationStack: [CurrentScreen]
    @State private var showingDeleteAlert = false
    @State private var itemToDelete: Vault? = nil
    @State private var showingExporter = false
    @State private var vaultToExport: Vault? = nil
    @State private var showEditVaultName = false
    @State private var vaultToEdit: Vault? = nil
    @State private var vaultEditName: String = ""
    @State private var expandedVaults: Set<Int> = []
    
    var body: some View {
        List(selection: $appState.currentVault) {
            ForEach(vaults.indices, id: \.self) { index in
                let vault = vaults[index]
                VStack {
                    HStack {
                        Button(action: {
                            self.appState.currentVault = vault
                            self.presentationStack.append(.listVaultAssetView)
                        }) {
                            HStack {
                                Text(vault.name.uppercased())
                                    .font(Font.custom("Menlo", size: 20).weight(.bold))
                                    .fontWeight(.black)
                                Spacer()
                            }
                            .padding() // Ensure there's some padding around the text for a larger clickable area
                            .frame(maxWidth: .infinity) // Ensure the HStack fills the button horizontally
                            .contentShape(Rectangle()) // Makes the entire area within the frame tappable
                        }
                        .buttonStyle(PlainButtonStyle()) // Maintains the button's style without additional effects
                        
                        Spacer()
                        Image(systemName: expandedVaults.contains(index) ? "chevron.up" : "chevron.down")
                            .onTapGesture {
                                if expandedVaults.contains(index) {
                                    expandedVaults.remove(index)
                                } else {
                                    expandedVaults.insert(index)
                                }
                            }
                    }
                    if expandedVaults.contains(index) {
                        Divider()
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Backup your vault").font(Font.custom("Menlo", size: 15))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle()) // Makes the entire area within the frame tappable
                        .padding()
                        .onTapGesture {
                            vaultToExport = vault
                            self.showingExporter = true
                        }
                        
                        HStack {
                            Image(systemName: "pencil")
                            Text("Edit your vault's name").font(Font.custom("Menlo", size: 15))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle()) // Makes the entire area within the frame tappable
                        .padding()
                        .onTapGesture {
                            self.vaultToEdit = vault
                            vaultEditName = vault.name
                            showEditVaultName = true
                        }
                        
                        HStack {
                            Image(systemName: "trash")
                            Button("Delete your vault permanently", role: .destructive) {
                                self.itemToDelete = vault
                                showingDeleteAlert = true
                            }
                            .font(Font.custom("Menlo", size: 15))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle()) // Makes the entire area within the frame tappable
                        .padding()
                    }
                }
            }
        }
        .sheet(isPresented: $showEditVaultName) {
            VStack {
                Form {
                    TextField("vault name", text: $vaultEditName)
                        .textFieldStyle(.roundedBorder)
                }.padding()
                
                HStack {
                    Button("Save") {
                        if let vaultToEdit = self.vaultToEdit {
                            vaultToEdit.name = vaultEditName
                                // Implement save functionality here
                        }
                        showEditVaultName.toggle()
                    }
                    Button("Cancel") {
                        showEditVaultName.toggle()
                    }
                }
                Spacer()
            }
        }
        .fileExporter(isPresented: $showingExporter, document: VoltixDocument(vault: vaultToExport), contentType: .data, defaultFilename: "\(vaultToExport?.name ?? "vault").dat") { result in
            switch result {
                case .failure(let err):
                    print("Fail to export, error: \(err.localizedDescription)")
                case .success(let url):
                    print("Exported to \(url)")
            }
        }
        .confirmationDialog("Delete Vault?", isPresented: $showingDeleteAlert, titleVisibility: .automatic) {
            Button("Confirm Delete \(itemToDelete?.name ?? "Vault")", role: .destructive) {
                if let itemToDelete = self.itemToDelete {
                    deleteVault(vault: itemToDelete)
                }
            }
        } message: {
            Text("Are you sure you want to delete this vault? This operation is not reversible.")
        }
        .navigationTitle("MY VAULTS".uppercased())
        .navigationBarBackButtonHidden()
        .modifier(InlineNavigationBarTitleModifier())
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                
                Button("New vault", systemImage: "plus.square.on.square") {
                    let vault = Vault(name: "Vault #\(vaults.count + 1)")
                    appState.creatingVault = vault
                    self.presentationStack.append(.newWalletInstructions)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    func deleteVault(vault: Vault) {
        modelContext.delete(vault)
        do {
            try modelContext.save()
        } catch {
            print("Error: \(error)")
        }
    }
}
