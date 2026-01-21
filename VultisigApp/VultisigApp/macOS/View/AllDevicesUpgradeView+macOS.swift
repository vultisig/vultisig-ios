//
//  AllDevicesUpgradeView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI

#if os(macOS)
extension AllDevicesUpgradeView {
    var content: some View {
        VStack {
            Spacer()
            animation
            Spacer()
            description
            button
        }
        .crossPlatformToolbar("Upgrade")
        .padding(.bottom, 30)
    }
}
#endif
