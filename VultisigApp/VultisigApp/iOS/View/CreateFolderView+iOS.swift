//
//  CreateFolderView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-07.
//

#if os(iOS)
import SwiftUI

extension CreateFolderView {
    var view: some View {
        VStack {
            content
            button
        }
        .navigationTitle(NSLocalizedString("createFolder", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
