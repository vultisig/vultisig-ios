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
            header
            Spacer()
            animation
            Spacer()
            description
            button
        }
        .padding(.bottom,30)
    }
    
    var header: some View {
        GeneralMacHeader(title: "Upgrade")
    }
}
#endif
