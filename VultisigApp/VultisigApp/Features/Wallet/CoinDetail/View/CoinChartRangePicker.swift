//
//  CoinChartRangePicker.swift
//  VultisigApp
//
//  Segmented pill for the coin-detail chart ranges. The selected pill is one
//  view that slides between slots via `matchedGeometryEffect`, rather than five
//  backgrounds fading in and out.
//

import SwiftUI

struct CoinChartRangePicker: View {
    let selected: MarketChartRange
    var onSelect: (MarketChartRange) -> Void

    @Namespace private var selectionNamespace

    private static let selectionID = "coinChartRangeSelection"

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MarketChartRange.allCases) { range in
                segment(for: range)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.colors.bgPrimary))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selected)
#if os(iOS)
        .sensoryFeedback(.selection, trigger: selected)
#endif
    }

    private func segment(for range: MarketChartRange) -> some View {
        Button {
            onSelect(range)
        } label: {
            Text(range.title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(range == selected ? Theme.colors.textPrimary : Theme.colors.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                // The label is drawn over the sliding pill, so the whole slot
                // stays tappable even before the pill arrives.
                .contentShape(Capsule())
                .background {
                    if range == selected {
                        Capsule()
                            .fill(Theme.colors.bgSurface2)
                            .matchedGeometryEffect(id: Self.selectionID, in: selectionNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(range.title)
        .accessibilityAddTraits(range == selected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    CoinChartRangePicker(selected: .week, onSelect: { _ in })
        .padding()
        .background(Theme.colors.bgSurface1)
}
