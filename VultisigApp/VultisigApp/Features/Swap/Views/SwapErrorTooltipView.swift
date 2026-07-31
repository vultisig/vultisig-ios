//
//  SwapErrorTooltipView.swift
//  VultisigApp
//
//  Created by Vultisig on 2025-01-09.
//

import SwiftUI

struct SwapErrorTooltipView: View {
    let error: Error
    @Binding var showTooltip: Bool
    let onDismissTooltip: () -> Void

    private let circleIconSize: CGFloat = 20
    private let circleIconPadding: CGFloat = 7
    private var circleSize: CGFloat {
        circleIconSize + circleIconPadding * 2
    }

    // Margin between the bottom of the warning circle and the top of the
    // tooltip's arrow tip.
    private let tooltipGap: CGFloat = 6
    // Fixed width so the tooltip wraps deterministically and its centered
    // arrow tip stays anchored to the circle regardless of message length.
    private let tooltipWidth: CGFloat = 240

    var body: some View {
        warningIcon
            .overlay(alignment: .top) {
                if showTooltip {
                    InfoTooltip(
                        title: errorTitle,
                        description: errorDescription,
                        arrowDirection: .up,
                        maxWidth: tooltipWidth,
                        onDismiss: onDismissTooltip
                    )
                    .frame(width: tooltipWidth)
                    .offset(y: circleSize + tooltipGap)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showTooltip)
    }

    var warningIcon: some View {
        Button {
            onDismissTooltip()
        } label: {
            Icon(.circleWarning, color: .white, size: circleIconSize)
                .padding(circleIconPadding)
                .background(Circle().fill(Theme.colors.alertError))
        }
    }

    // Title and body both come from `SwapErrorPresentation`, which owns the one
    // lookup they share. Resolving them separately in this view is what let a
    // domain-correct description sit under the generic "Unexpected Error"
    // heading: `SwapError` satisfied the description ladder's
    // `localizedDescription` fallback but matched none of the title ladder's arms.

    private var errorTitle: String {
        SwapErrorPresentation.title(for: error)
    }

    private var errorDescription: String {
        SwapErrorPresentation.message(for: error)
    }
}

#Preview {
    ZStack {
        Theme.colors.bgPrimary.ignoresSafeArea()

        SwapErrorTooltipView(
            error: SwapCryptoLogic.Errors.insufficientFunds,
            showTooltip: .constant(true),
            onDismissTooltip: {}
        )
    }
}
