//
//  FolderDetailView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-07.
//

#if os(macOS)
import SwiftUI

extension FolderDetailView {
    var view: some View {
        VStack(spacing: 0) {
            header
            content.padding(.top, 30)
            button
        }
    }
    
    var header: some View {
        HStack {
            backButton
            Spacer()
            title
            Spacer()
            navigationEditButton
        }
        .padding(.horizontal, 40)
        .foregroundColor(.neutral0)
        .font(.title3)
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
