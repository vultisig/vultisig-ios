//
//  LimitPriceChartDisclosure.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Price chart disclosure
//
// The chart is opt-in and starts collapsed. It is an optional way to set a price
// the form can already set numerically — the field and the preset pills stay
// visible either way — so it earns its vertical space only from users who ask
// for it, and costs no market-data traffic from the ones who don't.
//
// This is the single exception to the flat layout's "no collapse/expand" rule
// (see this file's header): that rule exists so the price and the amount it
// applies to are never hidden behind a chevron, and neither is. What collapses
// is one *way* of choosing the price, never the price itself.

struct LimitPriceChartDisclosure: View {

    @Bindable var vm: LimitSwapFormViewModel

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { vm.isChartExpanded },
            set: { vm.setChartExpanded($0, currency: SettingsCurrency.current) }
        )
    }

    var body: some View {
        ExpandableView(isExpanded: isExpanded) {
            header
        } content: {
            content
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("limitSwap.chart.title".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(Theme.fonts.caption10)
                .bold()
                .foregroundStyle(Theme.colors.textTertiary)
                .rotationEffect(.degrees(vm.isChartExpanded ? 180 : 0))
                .animation(.easeInOut(duration: 0.2), value: vm.isChartExpanded)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        if let chart = vm.pairChart {
            LimitPriceChartSection(vm: vm, chart: chart)
                .padding(.top, 4)
        } else if vm.isLoadingPairChart {
            // Reserves the chart's own height so expanding settles at its final
            // size once, instead of growing to a spinner and growing again to
            // the plot.
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: LimitPriceChartSection.chartHeight)
        } else {
            Text("limitSwap.chart.unavailable".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
        }
    }
}
