//
//  VultDiscountTierIcon.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/10/2025.
//

import SwiftUI
import VultisigUIResources

struct VultDiscountTierIcon: View {
    enum IconSize {
        case small
        /// Draws at exactly 36pt, where `.small` lays out at 42.
        case settingsSmall
        /// Draws at exactly 46pt.
        case settingsBig
    }
    let tier: VultDiscountTier
    let size: IconSize

    var iconSize: CGFloat {
        switch size {
        case .settingsBig:
            46
        case .small, .settingsSmall:
            36
        }
    }

    /// The glyphs have different aspect ratios, so only a fixed width keeps
    /// the settings badges the same size in a column.
    private var glyphWidth: CGFloat? {
        switch size {
        case .small:
            nil
        case .settingsBig, .settingsSmall:
            iconSize * 2 / 3
        }
    }

    private var glyphPadding: CGFloat {
        switch size {
        case .small:
            iconSize / 4
        case .settingsBig, .settingsSmall:
            iconSize / 6
        }
    }

    var body: some View {
        Image(tier.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: glyphWidth, height: iconSize * 2 / 3)
            .padding(glyphPadding)
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
                    .stroke(lineWidth: 1)
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
            VultisigImage("vult-ultimate-icon-overlay")
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
