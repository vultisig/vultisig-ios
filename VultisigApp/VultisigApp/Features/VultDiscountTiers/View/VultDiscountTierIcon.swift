//
//  VultDiscountTierIcon.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/10/2025.
//

import SwiftUI

struct VultDiscountTierIcon: View {
    enum IconSize {
        case big
        case small
    }
    let tier: VultDiscountTier
    let size: IconSize

    var iconSize: CGFloat {
        switch size {
        case .big:
            46
        case .small:
            36
        }
    }

    var borderWidth: CGFloat {
        switch size {
        case .big:
            2
        case .small:
            1
        }
    }

    var body: some View {
        Image(tier.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: iconSize * 2 / 3)
            .padding(iconSize / 4)
            .background(backgroundView.overlay(overlayView))
    }

    var backgroundView: some View {
        borderBgColor.opacity(0.12)
            .mask(Circle())
    }

    var overlayView: some View {
        borderBgColor
            .mask(
                Circle()
                    .inset(by: 1)
                    .stroke(lineWidth: borderWidth)
            )
    }

    @ViewBuilder
    var borderBgColor: some View {
        switch tier {
        case .bronze, .silver, .gold:
            tier.primaryColor
        case .platinum, .diamond:
            LinearGradient(
                colors: [
                    tier.primaryColor,
                    tier.secondaryColor
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .ultimate:
            Image("vult-ultimate-icon-overlay")
                .resizable()
        }
    }
}

#Preview {
    VStack {
        ForEach(VultDiscountTier.allCases) {
            VultDiscountTierIcon(tier: $0, size: .small)
        }
    }
}
