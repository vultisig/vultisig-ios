//
//  YieldInfoLabel.swift
//  VultisigApp
//

import SwiftUI

/// Identifies which yield info-tooltip is currently open, so only one popover
/// shows at a time across the dashboard rows.
enum YieldTooltipID: Hashable {
    case apy
    case rewards
    case overview
}

/// A row leading-label (leading icon + text) with a trailing 16×16 ⓘ button
/// that toggles an anchored `InfoTooltip` popover below it. Reuses the
/// design-system `InfoTooltip` (rounded card + arrow + title + ✕ + body).
struct YieldInfoLabel: View {
    let icon: String
    let isSystemIcon: Bool
    let label: String
    let tooltipID: YieldTooltipID
    let tooltipTitle: String
    let tooltipBody: String
    @Binding var openTooltip: YieldTooltipID?

    private var isOpen: Bool { openTooltip == tooltipID }

    var body: some View {
        HStack(spacing: 6) {
            Icon(named: icon, color: Theme.colors.textTertiary, size: 16, isSystem: isSystemIcon)
            Text(label)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    openTooltip = isOpen ? nil : tooltipID
                }
            } label: {
                Icon(named: "circle-info", color: Theme.colors.textTertiary, size: 16)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topLeading) {
                if isOpen {
                    InfoTooltip(
                        title: tooltipTitle,
                        description: tooltipBody,
                        arrowDirection: .up,
                        arrowXFraction: 0.12,
                        maxWidth: 260,
                        onDismiss: { openTooltip = nil }
                    )
                    .fixedSize()
                    .offset(x: -24, y: 22)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                    .zIndex(1)
                }
            }
        }
    }
}
