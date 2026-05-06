//
//  SwapModeTabBar.swift
//  VultisigApp
//

import SwiftUI

enum SwapMode: Equatable {
    case market
    case limit
}

/// Top-of-screen tab bar for the Swap feature. `Market` always available;
/// `Limit` disabled when the current pair isn't routable through THORChain.
/// Caller must hide the entire bar when the limit-swap feature flag is off.
struct SwapModeTabBar: View {

    @Binding var selectedMode: SwapMode
    let isLimitDisabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            tab(mode: .market, titleKey: "swap.tab.market", isEnabled: true)
            tab(mode: .limit, titleKey: "swap.tab.limit", isEnabled: !isLimitDisabled)
        }
    }

    private func tab(mode: SwapMode, titleKey: String, isEnabled: Bool) -> some View {
        Button {
            guard isEnabled else { return }
            selectedMode = mode
        } label: {
            VStack(spacing: 6) {
                Text(titleKey.localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(textColor(for: mode, isEnabled: isEnabled))
                    .frame(minWidth: 60)
                    .padding(.horizontal, 8)

                Rectangle()
                    .fill(selectedMode == mode ? Theme.colors.textPrimary : Color.clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func textColor(for mode: SwapMode, isEnabled: Bool) -> Color {
        if !isEnabled {
            return Theme.colors.textTertiary.opacity(0.5)
        }
        return selectedMode == mode ? Theme.colors.textPrimary : Theme.colors.textTertiary
    }
}
