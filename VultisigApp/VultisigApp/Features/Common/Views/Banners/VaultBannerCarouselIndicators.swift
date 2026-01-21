//
//  VaultBannerCarouselIndicators.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 08/10/2025.
//

import SwiftUI

struct VaultBannerCarouselIndicators: View {
    @Binding var currentIndex: Int
    @Binding var bannersCount: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<bannersCount, id: \.self) { index in
                VaultBannerCarouselIndicator(
                    indicatorIndex: index,
                    currentIndex: $currentIndex,
                    bannersCount: bannersCount
                )
            }
        }
    }
}
