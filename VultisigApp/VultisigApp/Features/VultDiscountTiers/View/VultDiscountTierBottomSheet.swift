//
//  VultDiscountTierBottomSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/10/2025.
//

import SwiftUI

struct VultDiscountTierBottomSheet: View {
    let tier: VultDiscountTier
    @Binding var isPresented: Bool
    var onUnlock: () -> Void
    
    @State var width: CGFloat = 0
    
    var descriptionText: String {
        switch tier {
        case .ultimate:
            String(
                format: "unlockUltimateTierDescription".localized,
                tier.balanceToUnlock.formatForDisplay()
            )
        default:
            String(
                format: "unlockXTierDescription".localized,
                tier.balanceToUnlock.formatForDisplay(),
                tier.name.localized,
                "\(tier.bpsDiscount)"
            )
        }
    }
    
    var highlightedDescriptionText: String {
        switch tier {
        case .ultimate:
            "unlockUltimateTierDescriptionHighlighted".localized
        default:
            String(
                format: "unlockXTierDescriptionHighlighted".localized,
                "\(tier.bpsDiscount)"
            )
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                VultDiscountTierIcon(tier: tier, size: .big)
                    .padding(.bottom, 6)
                Group {
                    if tier == .ultimate {
                        makeUltimateTitleText()
                    } else {
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
                }

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
            }
            Spacer()
            PrimaryButton(
                title: "unlockTier".localized,
                action: onUnlock
            )
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
        #if os(macOS)
        .padding(.bottom, 24)
        .applySheetSize(400, 350)
        #endif
        .background(ModalBackgroundView(width: width))
        .presentationBackground(Theme.colors.bgSecondary)
        .presentationDetents([.height(350)])
        .presentationDragIndicator(.visible)
        .readSize {
            width = $0.width
        }
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: false) {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    isPresented.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private func makeUltimateTitleText() -> some View {
        let fullText = String(format: "unlockXTier".localized, tier.name.localized)
        let highlightText = tier.name.localized

        // Find the range of the highlighted text
        if let range = fullText.range(of: highlightText) {
            let beforeText = String(fullText[..<range.lowerBound])
            let afterText = String(fullText[range.upperBound...])

            // Compose the text with image overlay on highlighted portion
            HStack(spacing: 0) {
                if !beforeText.isEmpty {
                    Text(beforeText)
                        .font(Theme.fonts.title1)
                        .foregroundColor(Theme.colors.textPrimary)
                }

                Text(highlightText)
                    .font(Theme.fonts.title1)
                    .foregroundColor(.clear)
                    .overlay {
                        Image("vult-ultimate-box-overlay")
                            .resizable()
                            .scaledToFill()
                            .mask(
                                Text(highlightText)
                                    .font(Theme.fonts.title1)
                            )
                    }

                if !afterText.isEmpty {
                    Text(afterText)
                        .font(Theme.fonts.title1)
                        .foregroundColor(Theme.colors.textPrimary)
                }
            }
        } else {
            // Fallback if highlighted text not found
            Text(fullText)
                .font(Theme.fonts.title1)
                .foregroundColor(Theme.colors.textPrimary)
        }
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
        VultDiscountTierBottomSheet(tier: tier, isPresented: .constant(true)) {}
    }
}
