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
                        HighlightedTextWithImage(
                            text: String(format: "unlockXTier".localized, tier.name.localized),
                            highlightedText: tier.name.localized,
                            imageName: "vult-ultimate-text-overlay",
                            font: Theme.fonts.title1,
                            foregroundColor: Theme.colors.textPrimary
                        )
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
                    attrString.foregroundColor = Theme.colors.textSecondary
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
        .applySheetSize(400, 300)
        #endif
        .background(ModalBackgroundView(width: width))
        .presentationBackground(Theme.colors.bgSurface1)
        .presentationDetents([.height(300)])
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
