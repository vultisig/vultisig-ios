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

    #if os(macOS)
        private let tooltipGap: CGFloat = 30 // Slightly more offset on macOS
    #else
        private let tooltipGap: CGFloat = 24
    #endif

    var body: some View {
        warningIcon
            .overlay(alignment: .top) {
                if showTooltip {
                    InfoTooltip(
                        title: errorTitle,
                        description: errorDescription,
                        arrowDirection: .up,
                        onDismiss: onDismissTooltip
                    )
                    .fixedSize(horizontal: true, vertical: true)
                    .offset(y: circleSize + tooltipGap)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showTooltip)
    }

    var warningIcon: some View {
        Button {
            showTooltip.toggle()
        } label: {
            Icon(named: "circle-warning", color: .white, size: circleIconSize)
                .padding(circleIconPadding)
                .background(Circle().fill(Theme.colors.alertError))
        }
    }

    private var errorTitle: String {
        if let swapError = error as? SwapCryptoLogic.Errors {
            return swapError.errorTitle
        }
        if let swapError = error as? SwapError {
            return title(for: swapError)
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

    /// Domain-appropriate title for the swap-flow's `SwapError` cases. Without
    /// this branch a `SwapError` (e.g. `.routeUnavailable` raised when SwapKit
    /// reports no route for the pair) would fall through to the generic
    /// "Unexpected Error" title even though its `errorDescription` is specific.
    private func title(for swapError: SwapError) -> String {
        switch swapError {
        case .routeUnavailable, .noLiquidityPool:
            return "swapErrorRouteUnavailableTitle".localized
        case .swapAmountTooSmall, .lessThenMinSwapAmount:
            return SwapCryptoLogic.Errors.swapAmountTooSmall.errorTitle
        case .serverError:
            return SwapCryptoLogic.Errors.unexpectedError.errorTitle
        }
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
