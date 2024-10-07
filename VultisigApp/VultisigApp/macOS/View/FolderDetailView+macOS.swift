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
            headerMac
            Separator()
            content
            button
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: vaultFolder.folderName)
            .padding(.bottom, 8)
    }
}
#endif
