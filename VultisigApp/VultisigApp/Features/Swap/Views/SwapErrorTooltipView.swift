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
        return SwapCryptoLogic.Errors.unexpectedError.errorTitle
    }

    private var errorDescription: String {
        if let swapError = error as? SwapCryptoLogic.Errors {
            return swapError.errorDescription ?? error.localizedDescription
        }
        return error.localizedDescription
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
