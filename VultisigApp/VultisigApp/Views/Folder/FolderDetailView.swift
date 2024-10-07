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
        }
    }
    
    var content: some View {
        ScrollView {
            selectedVaultsList
            remainingVaultsList
        }
    }
    
    var navigationEditButton: some View {
        Button {
            withAnimation {
                isEditing.toggle()
            }
        } label: {
            if isEditing {
                doneLabel
            } else {
                editIcon
            }
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
    
    var editIcon: some View {
        Image(systemName: "square.and.pencil")
            .foregroundColor(Color.neutral0)
            .font(.body18MenloBold)
    }
    
    var doneLabel: some View {
        Text(NSLocalizedString("done", comment: ""))
            .foregroundColor(Color.neutral0)
            .font(.body18MenloBold)
    }
}

#Preview {
    FolderDetailView(vaultFolder: VaultFolder.example)
}
