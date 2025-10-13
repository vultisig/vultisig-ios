//
//  VultDiscountTierBottomSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/10/2025.
//

import SwiftUI

struct VultDiscountTierBottomSheet: View {
    let tier: VultDiscountTier
    var onUnlock: () -> Void
    
    @State var width: CGFloat = 0
    
    var descriptionText: String {
        String(
            format: "unlockXTierDescription".localized,
            tier.balanceToUnlock.toDecimal(decimals: 0).formatForDisplay(),
            tier.name.localized,
            "\(tier.bpsDiscount)"
        )
    }
    
    var highlightedDescriptionText: String {
        String(
            format: "unlockXTierDescriptionHighlighted".localized,
            "\(tier.bpsDiscount)"
        )
    }
    
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                VStack(spacing: 24) {
                    VultDiscountTierIcon(tier: tier, size: 72)
                    HighlightedText(
                        text: String(format: "unlockXTier".localized, tier.name.localized),
                        highlightedText: tier.name.localized
                    ) { attrString in
                        attrString.font = Theme.fonts.title1
                        attrString.foregroundColor = Theme.colors.textPrimary
                    } highlightedTextStyle: { attrString in
                        attrString.foregroundColor = tier.primaryColor
                    }
                }
                Spacer()
                HighlightedText(
                    text: descriptionText,
                    highlightedText: highlightedDescriptionText
                ) { attrString in
                    attrString.font = Theme.fonts.bodySRegular
                    attrString.foregroundColor = Theme.colors.textLight
                } highlightedTextStyle: { attrString in
                    attrString.font = Theme.fonts.bodySMedium
                    attrString.foregroundColor = Theme.colors.textPrimary
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                Spacer()
                PrimaryButton(
                    title: "unlockTier".localized,
                    action: onUnlock
                )
            }
            .padding(.top, 40)
            .padding(.horizontal, 24)
            .background(ModalBackgroundView(width: width))
            .presentationBackground(Theme.colors.bgSecondary)
            .presentationDetents([.height(375)])
            .presentationDragIndicator(.visible)
            .applySheetSize()
            .readSize {
                width = $0.width
            }
        }
        .crossPlatformToolbar(ignoresTopEdge: true)
    }
}

#Preview {
    @Previewable @State var showSheet: VultDiscountTier?
    VStack {
        ForEach(VultDiscountTier.allCases) { tier in
            PrimaryButton(title: "Show \(tier.name) sheet") {
                showSheet = tier
            }
        }
    }
    .crossPlatformSheet(item: $showSheet) { tier in
        VultDiscountTierBottomSheet(tier: tier) {}
    }
}
