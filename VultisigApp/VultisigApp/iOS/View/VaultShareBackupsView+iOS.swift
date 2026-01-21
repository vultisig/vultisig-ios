//
//  VaultShareBackupsView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI

#if os(iOS)
extension VaultShareBackupsView {
    var content: some View {
        ZStack {
            VStack {
                image
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()
                description
                button
            }
        }
        .padding(36)
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
    }
}
#endif
