//
//  AllDevicesUpgradeView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI

#if os(iOS)
extension AllDevicesUpgradeView {
    var content: some View {
        VStack(spacing: 0) {
            Spacer()
            animation
            Spacer()
            description
            button
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
