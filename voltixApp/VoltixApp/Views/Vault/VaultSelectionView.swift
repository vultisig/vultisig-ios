    //
    //  VaultSelection.swift
    //  VoltixApp
    //

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
        // New state to manage expanded/collapsed state, using the vault index in the array
    @State private var expandedVaults: Set<Int> = []
    
    var body: some View {
        List(selection: $appState.currentVault) {
            ForEach(vaults.indices, id: \.self) { index in
                let vault = vaults[index]
                VStack {
                    HStack {
                        NavigationLink(destination: ListVaultAssetView(presentationStack: $presentationStack),
                                       label: {
                            Text(vault.name)
                                .swipeActions {
                                    Button("Delete", role: .destructive) {
                                        self.itemToDelete = vault
                                        showingDeleteAlert = true
                                    }
                                }
                        })
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
                        // Conditionally show details
                    if expandedVaults.contains(index) {
                        Divider()
                        HStack {
                            Image(systemName: "icloud.and.arrow.up")
                            Text("Backup your vault")
                            Spacer()
                        }
                        .padding()
                        .onTapGesture {
                            vaultToExport = vault
                            self.showingExporter = true
                        }
                        
                        HStack {
                            Image(systemName: "pencil")
                            Text("Edit your vault's name")
                            Spacer()
                        }
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
                            Spacer()
                        }
                        .padding()
                        
                    }
                }
            }
        }
        .sheet(isPresented: $showEditVaultName, content: {
            VStack{
                Form{
                    TextField("vault name", text: $vaultEditName)
                        .textFieldStyle(.roundedBorder)
                }.padding()
                
                HStack{
                    Button("Save"){
                        self.vaultToEdit?.name = vaultEditName
                        showEditVaultName.toggle()
                    }
                    Button("cancel"){
                        showEditVaultName.toggle()
                    }
                }
                Spacer()
            }
        })
        .fileExporter(isPresented: $showingExporter,
                      document: VoltixDocument(vault: vaultToExport),
                      contentType: .data,
                      defaultFilename: "\(vaultToExport?.name ?? "vault").dat",
                      onCompletion: { result in
            switch result {
                case .failure(let err):
                    print("fail to export,error:\(err.localizedDescription)")
                case .success(let url):
                    print("exported to \(url)")
            }
        })
        .confirmationDialog(Text("Delete Vault"), isPresented: $showingDeleteAlert, titleVisibility: .automatic) {
            Button("Confirm Delete \(itemToDelete?.name ?? "Vault")", role: .destructive) {
                withAnimation {
                    if let itemToDelete {
                        deleteVault(vault: itemToDelete)
                    }
                }
            }
        } message: {
            Text("Are you sure want to delete selected vault? \n Operation is not reversable")
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
            print("Error:\(error)")
        }
    }
}
