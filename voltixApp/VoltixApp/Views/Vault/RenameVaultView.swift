//
//  RenameVaultView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-12.
//

import SwiftUI

struct RenameVaultView: View {
    let vault: Vault
    
    @State var name = ""
    
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("renameVault", comment: "Edit Rename Vault View title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
        .onAppear {
            setData()
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack {
            content
            Spacer()
            button
        }
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
    }
    
    var button: some View {
        FilledButton(title: "save")
            .padding(40)
    }
    
    private func setData() {
        name = vault.name
    }
}

#Preview {
    RenameVaultView(vault: Vault.example)
}
