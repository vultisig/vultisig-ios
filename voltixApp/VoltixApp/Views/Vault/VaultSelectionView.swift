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
    @Environment(\.colorScheme) var colorScheme
    
    private var cardBackgroundColor: Color {
        switch colorScheme {
            case .light:
                return Color(UIColor.systemFill)
            case .dark:
                return Color(UIColor.secondarySystemGroupedBackground)
            @unknown default:
                return Color(UIColor.systemBackground)
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack {
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
                                    Spacer()
                                }
                                .padding() // Ensure there's some padding around the text for a larger clickable area
                                .frame(maxWidth: .infinity) // Ensure the HStack fills the button horizontally
                                .contentShape(Rectangle()) // Makes the entire area within the frame tappable

                            }
                            .buttonStyle(PlainButtonStyle())
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
                            VStack(spacing: 15) {
                                Divider()
                                
                                Button(action: {
                                    vaultToExport = vault
                                    showingExporter = true
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.down.circle")
                                        Text("Backup your vault")
                                            .font(Font.custom("Menlo", size: 15))
                                        Spacer()
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding()
                                .background(cardBackgroundColor)
                                .cornerRadius(10)
                                
                                Button(action: {
                                    vaultToEdit = vault
                                    vaultEditName = vault.name
                                    showEditVaultName = true
                                }) {
                                    HStack {
                                        Image(systemName: "pencil")
                                        Text("Edit your vault's name")
                                            .font(Font.custom("Menlo", size: 15))
                                        Spacer()
                                    }
                                }
                                .padding()
                                .buttonStyle(PlainButtonStyle())
                                .background(cardBackgroundColor)
                                .cornerRadius(10)
                                
                                Button(action: {
                                    itemToDelete = vault
                                    showingDeleteAlert = true
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Delete your vault permanently")
                                            .font(Font.custom("Menlo", size: 15))
                                        Spacer()
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding()
                                .background(cardBackgroundColor)
                                .foregroundColor(.red)
                                .cornerRadius(10)
                                .confirmationDialog("Delete Vault?", isPresented: $showingDeleteAlert, titleVisibility: .automatic) {
                                    Button("Confirm Delete \(itemToDelete?.name ?? "Vault")", role: .destructive) {
                                        if let itemToDelete = self.itemToDelete {
                                            deleteVault(vault: itemToDelete)
                                        }
                                    }
                                } message: {
                                    Text("Are you sure you want to delete this vault? This operation is not reversible.")
                                }

                            }
                            .padding(.top, 10)
                        }
                    }
                    .padding(.vertical, 15)
                    .padding()
                    .background(cardBackgroundColor)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .animation(.default, value: expandedVaults.contains(index))
                }
            }
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .navigationTitle("MY VAULTS")
        .modifier(InlineNavigationBarTitleModifier())
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                
                Button("New vault", systemImage: "plus.square.on.square") {
                    let vault = Vault(name: "Vault #\(vaults.count + 1)")
                    appState.creatingVault = vault
                    self.presentationStack.append(.startScreen)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .sheet(isPresented: $showEditVaultName) {
            VStack {
                Form {
                    TextField("Vault name", text: $vaultEditName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }.padding()
                HStack {
                    Button("Save") {
                        if let vaultToEdit = self.vaultToEdit {
                            vaultToEdit.name = vaultEditName
                                // Implement save functionality here
                        }
                        showEditVaultName = false
                    }
                    Button("Cancel") {
                        showEditVaultName = false
                    }
                }
                Spacer()
            }
        }
        .fileExporter(isPresented: $showingExporter, document: VoltixDocument(vault: vaultToExport), contentType: .data, defaultFilename: "\(vaultToExport?.name ?? "vault").dat") { result in
            switch result {
                case .failure(let error):
                    print("Fail to export, error: \(error.localizedDescription)")
                case .success(let url):
                    print("Exported to \(url)")
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
