//
//  CreateFolderView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-07.
//

#if os(macOS)
import SwiftUI

extension CreateFolderView {
    var view: some View {
        VStack(spacing: 0) {
            headerMac
            Separator()
            content
            button
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "createFolder")
            .padding(.bottom, 8)
    }
}
#endif
