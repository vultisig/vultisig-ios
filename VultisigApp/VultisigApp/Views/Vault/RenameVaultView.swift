//
//  RenameVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import SwiftUI
import SwiftData

struct RenameVaultView: View {
    let vaults: [Vault]
    let vault: Vault
    
    @State var name = ""
    @Environment(\.dismiss) var dismiss
    @State var showAlert: Bool = false
    @State var errorMessage: String = ""
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        ZStack {
            Background()
            main
        }
#if os(iOS)
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("renameVault", comment: "Edit Rename Vault View title"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
#endif
        .onAppear {
            setData()
        }
    }
    
    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "renameVault")
    }
    
    var view: some View {
        VStack {
            content
            Spacer()
            button
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(NSLocalizedString("error", comment: "")),
                message: Text(errorMessage),
                dismissButton: .default(Text("ok"))
            )
        }
#if os(macOS)
        .padding(.horizontal, 25)
#endif
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("vaultName", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
            
            textfield
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }
    
    var textfield: some View {
        TextField(NSLocalizedString("typeHere", comment: "").capitalized, text: $name)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .submitLabel(.done)
            .padding(12)
            .background(Color.blue600)
            .cornerRadius(12)
            .borderlessTextFieldStyle()
            .maxLength($name)
    }
    
    var button: some View {
        Button {
            rename()
        } label: {
            FilledButton(title: "save")
        }
        .padding(40)
    }
    
    private func setData() {
        name = vault.name
    }
    
    private func rename() {
        // make sure the same vault name has not been occupied
        if vaults.contains(where: { $0.name == name && $0.pubKeyECDSA != vault.pubKeyECDSA && $0.pubKeyEdDSA != vault.pubKeyEdDSA}) {
            errorMessage = NSLocalizedString("vaultNameExists", comment: "").replacingOccurrences(of: "%s", with: name)
            name = vault.name
            showAlert = true
            return
        }
        
        vault.name = name
        homeViewModel.selectedVault = vault
        homeViewModel.vaultName = name
        dismiss()
    }
}

#Preview {
    RenameVaultView(vaults:[],vault: Vault.example)
        .environmentObject(HomeViewModel())
}
