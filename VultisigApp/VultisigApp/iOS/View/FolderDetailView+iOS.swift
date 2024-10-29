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
}
#endif
