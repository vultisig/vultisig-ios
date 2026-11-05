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
    @State private var contentHeight: CGFloat = 0

    private let minimumSheetHeight: CGFloat = 372
    private let homeIndicatorHeight: CGFloat = 34

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
                "\(tier.percentOffFee)"
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
                "\(tier.percentOffFee)"
            )
        }
    }

    var body: some View {
        sheetContent
        .padding(.top, 53)
        .padding(.horizontal, 30)
        .padding(.bottom, 33)
        .fixedSize(horizontal: false, vertical: true)
        .readSize {
            width = $0.width
            contentHeight = $0.height
        }
        .frame(maxHeight: .infinity, alignment: .top)
        #if os(macOS)
        .applySheetSize(400, sheetHeight)
        #endif
        .background(ModalBackgroundView(width: width))
        .presentationBackground(Theme.colors.bgSurface1)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: false) {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: .xmark) {
                    isPresented.toggle()
                }
            }
        }
    }

    private var sheetContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 26) {
                VultDiscountTierIcon(tier: tier, size: .settingsBig)
                Text(String(format: "unlockXTier".localized, tier.name.localized))
                    .settingsText(.title1)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HighlightedText(
                text: descriptionText,
                highlightedText: highlightedDescriptionText
            ) { attrString in
                attrString.font = Theme.fonts.bodySRegular
                attrString.foregroundColor = Theme.colors.textSecondary
            } highlightedTextStyle: { attrString in
                attrString.font = Theme.fonts.buttonSSemibold
                attrString.foregroundColor = Theme.colors.textPrimary
            }
            .settingsText(.bodySRegular)
            .multilineTextAlignment(.center)

            PrimaryButton(
                title: "unlockTier".localized,
                size: .compactSemibold,
                action: onUnlock
            )
        }
    }

    /// Grows past the design's height when a long locale wraps the body.
    private var sheetHeight: CGFloat {
        max(minimumSheetHeight, contentHeight + homeIndicatorHeight)
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
