//
//  UpgradeYourVaultView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI

#if os(macOS)
extension UpgradeYourVaultView {
    var container: some View {
        content
            .frame(width: 500, height: 700)
    }
}
#endif
