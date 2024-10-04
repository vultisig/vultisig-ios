//
//  FolderDetailView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-04.
//

import SwiftUI

struct FolderDetailView: View {
    let vaultFolder: VaultFolder
    
    @State var isEditing = false
    
    var body: some View {
        ZStack {
            Background()
            view
            Button {
                withAnimation {
                    isEditing.toggle()
                }
            } label: {
                Text("TOGGLE")
            }
        }
        .navigationTitle(NSLocalizedString(vaultFolder.folderName, comment: ""))
    }
    
    var view: some View {
        VStack {
            content
            button
        }
    }
    
    var content: some View {
        ScrollView {
            selectedVaultsList
            remainingVaultsList
        }
    }
    
    var selectedVaultsList: some View {
        VStack(spacing: 16) {
            
        }
        .padding(.top, 30)
        .padding(.horizontal, 16)
    }
    
    var remainingVaultsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            vaultsTitle
            vaultsList
        }
        .padding(.horizontal, 16)
    }
    
    var vaultsTitle: some View {
        Text(NSLocalizedString("addVaultsToFolder", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratSemiBold)
    }
    
    var vaultsList: some View {
        VStack(spacing: 16) {
            
        }
    }
    
    var button: some View {
        FilledButton(title: "deleteFolder", background: Color.miamiMarmalade)
            .padding(16)
            .edgesIgnoringSafeArea(.bottom)
            .frame(maxHeight: isEditing ? nil : 0)
            .clipped()
            .background(Color.backgroundBlue)
    }
}

#Preview {
    FolderDetailView(vaultFolder: VaultFolder.example)
}
