//
//  VaultShareBackupsView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI

#if os(macOS)
extension VaultShareBackupsView {
    var content: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            image
            Spacer()
            description
            button
        }
        .padding(36)
    }
    
    var header: some View {
        GeneralMacHeader(title: "")
    }
}
#endif
