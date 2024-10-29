//
//  FolderDetailView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-07.
//

#if os(iOS)
import SwiftUI

extension FolderDetailView {
    var view: some View {
        VStack {
            header
            content
            button
        }
        .navigationTitle(vaultFolder.folderName)
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                navigationEditButton
            }
        }
    }
    
    var header: some View {
        HStack {
            backButton
            Spacer()
            title
            Spacer()
            backButton.opacity(0)
        }
        .padding(.horizontal, 16)
        .foregroundColor(.neutral0)
        .font(.body)
        .fontWeight(.bold)
        .padding(.top, 24)
    }
    
    var backButton: some View {
        Button {
            showFolderDetails = false
        } label: {
            Image(systemName: "chevron.backward")
                .foregroundColor(.neutral0)
                .font(.body)
        }
    }
    
    var title: some View {
        Text(NSLocalizedString(vaultFolder.folderName, comment: ""))
    }
}
#endif
