//
//  CustomizeChainsActionBanner.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import SwiftUI

struct CustomizeChainsActionBanner: View {
    let showButton: Bool
    var onCustomizeChains: () -> Void

    var body: some View {
        ActionBannerView(
            title: "noChainsFound".localized,
            subtitle: "noChainsFoundSubtitle".localized,
            buttonTitle: "customizeChains".localized,
            buttonIcon: "crypto-wallet-pen",
            showsActionButton: showButton,
            action: onCustomizeChains
        )
    }
}

#Preview {
    CustomizeChainsActionBanner(showButton: true, onCustomizeChains: {})
}
