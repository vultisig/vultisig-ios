//
//  CreateFolderView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-03.
//

import SwiftUI

struct CreateFolderView: View {
    @State var name = ""
    @State var selectedVaults: [Vault] = []
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Background()
            view
        }
        .navigationTitle(NSLocalizedString("createFolder", comment: ""))
    }
    
    var view: some View {
        VStack {
            content
            button
        }
    }
    
    var content: some View {
        ScrollView {
            folderName
            vaultList
        }
    }
    
    var button: some View {
        FilledButton(title: "create")
            .padding(16)
    }
    
    var folderName: some View {
        VStack(alignment: .leading, spacing: 12) {
            folderNameTitle
            folderNameTextField
        }
        .padding(.horizontal, 16)
    }
    
    var folderNameTitle: some View {
        Text(NSLocalizedString("folderName", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratSemiBold)
    }
    
    var folderNameTextField: some View {
        TextField(
            NSLocalizedString("typeHere", comment: ""),
            text: $name
        )
        .font(.body14Menlo)
        .foregroundColor(.neutral0)
        .submitLabel(.done)
        .padding(12)
        .padding(.vertical, 3)
        .background(Color.blue600)
        .cornerRadius(12)
        .colorScheme(.dark)
    }
    
    var vaultList: some View {
        VStack(alignment: .leading, spacing: 12) {
            vaultsTitle
            list
        }
        .padding(.horizontal, 16)
    }
    
    var vaultsTitle: some View {
        Text(NSLocalizedString("addVaultsToFolder", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratSemiBold)
            .padding(.top, 22)
    }
    
    var list: some View {
        VStack(spacing: 6) {
            
        }
    }
}

#Preview {
    CreateFolderView()
}
