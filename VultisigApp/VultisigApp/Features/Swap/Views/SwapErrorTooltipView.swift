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

    private var errorTitle: String {
        if let swapError = error as? SwapCryptoLogic.Errors {
            return swapError.errorTitle
        }
        if let normalized = normalizedSwapKitError {
            return normalized.errorTitle
        }
        return SwapCryptoLogic.Errors.unexpectedError.errorTitle
    }

    private var errorDescription: String {
        if let swapError = error as? SwapCryptoLogic.Errors {
            return swapError.errorDescription ?? error.localizedDescription
        }
        if let normalized = normalizedSwapKitError {
            return normalized.errorDescription ?? error.localizedDescription
        }
        return error.localizedDescription
    }

    /// Map terminal SwapKit error cases onto the swap-flow's user-facing
    /// error vocabulary so the tooltip shows a domain-appropriate title and
    /// description instead of the generic "Unexpected Error" fallback. Only
    /// covers cases that have a clear `SwapCryptoLogic.Errors` equivalent —
    /// everything else flows through `error.localizedDescription` as before.
    private var normalizedSwapKitError: SwapCryptoLogic.Errors? {
        guard let swapKitError = error as? SwapKitError else { return nil }
        switch swapKitError {
        case .amountBelowProviderMinimum:
            return .swapAmountTooSmall
        default:
            return nil
        }
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
