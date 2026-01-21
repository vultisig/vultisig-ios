//
//  CustomizeChainsActionBanner.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import SwiftUI

struct CustomizeChainsActionBanner: View {
    var onCustomizeChains: () -> Void

    var body: some View {
        ActionBannerView(
            title: "noChainsFound".localized,
            subtitle: "noChainsFoundSubtitle".localized,
            buttonTitle: "customizeChains".localized,
            action: onCustomizeChains
        )
    }
}

#Preview {
    CustomizeChainsActionBanner(onCustomizeChains: {})
}
