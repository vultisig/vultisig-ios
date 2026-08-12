//
//  LimitPriceChartSection.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Price chart section
//
// The chart, the window picker under it, and the one-line verdict on whether the
// pair has ever been where the target is. The verdict is the part that answers
// the question a limit price actually raises — "is this reachable?" — and is
// also the part that makes the expiry pills legible.

struct LimitPriceChartSection: View {

    @Bindable var vm: LimitSwapFormViewModel
    let chart: MarketChart

    /// Ranges offered here, deliberately not `MarketChartRange.allCases`. `1D`
    /// is omitted: the drag zone spans the preset pills' reach, ~15%, and an
    /// intraday range is a fraction of that, so the history draws as a flat
    /// ribbon whatever the domain policy. Coin detail keeps 1D because there the
    /// plot is only ever a picture; here it is also an input.
    private static let ranges: [MarketChartRange] = [.week, .month, .year, .all]

    /// Shared with the disclosure's loading placeholder so expanding settles at
    /// its final height once rather than growing twice.
    static let chartHeight: CGFloat = 148

    private var market: Double? {
        vm.marketPriceRef.map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    private var target: Double {
        NSDecimalNumber(decimal: vm.draft.targetPrice).doubleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LimitPriceChartView(
                chart: chart,
                market: market,
                target: target,
                targetLabel: targetLabel,
                onTargetChanged: vm.targetPriceChangedFromChart
            )
            .frame(height: Self.chartHeight)
            .opacity(vm.isLoadingPairChart ? 0.45 : 1)
            // The outgoing series stays on screen, dimmed, while the next one
            // loads. Clearing it first collapses the card and the whole form
            // jumps — worse, on a range switch, than a briefly stale line.
            .animation(.easeInOut(duration: 0.2), value: vm.isLoadingPairChart)

            reachHint

            LimitChartRangePills(vm: vm, ranges: Self.ranges)
        }
    }

    private var targetLabel: String {
        "\(formatPrice(vm.draft.targetPrice)) \(vm.draft.toAsset.ticker)"
    }

    @ViewBuilder
    private var reachHint: some View {
        // Evaluated once and threaded through both consumers. Read as two
        // computed properties, the reach scan walked the whole series twice on
        // every body pass.
        let reach = verdict
        HStack(spacing: 6) {
            Circle()
                .fill(hintTint(for: reach))
                .frame(width: 5, height: 5)
            Text(hintText(for: reach))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var verdict: LimitChartReach.Verdict {
        // Same non-finite filter the chart layout applies to this series. On the
        // raw points a NaN or infinite sample survives into `.notReached(highest:)`
        // and reaches `Decimal(_: Double)`, which represents neither — so the
        // hint would render from a value the chart itself had already discarded.
        let sanitised = MarketChart(points: chart.points.filter(\.price.isFinite))
        return LimitChartReach.evaluate(chart: sanitised, target: target, market: market)
    }

    private func hintTint(for verdict: LimitChartReach.Verdict) -> Color {
        switch verdict {
        case .atOrBelowMarket: return Theme.colors.alertError
        case .lastTraded: return Theme.colors.alertSuccess
        case .notReached: return Theme.colors.textTertiary
        }
    }

    private func hintText(for verdict: LimitChartReach.Verdict) -> String {
        switch verdict {
        case .atOrBelowMarket:
            return "limitSwap.chart.fillsImmediately".localized
        case .lastTraded(let date):
            let elapsed = RelativeDateTimeFormatter()
            elapsed.unitsStyle = .full
            return String(
                format: "limitSwap.chart.lastTradedHere".localized,
                elapsed.localizedString(for: date, relativeTo: Date())
            )
        case .notReached(let highest):
            return String(
                format: "limitSwap.chart.notReached".localized,
                "\(formatPrice(Decimal(highest))) \(vm.draft.toAsset.ticker)"
            )
        }
    }

    private func formatPrice(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }
}

private struct LimitChartRangePills: View {

    @Bindable var vm: LimitSwapFormViewModel
    let ranges: [MarketChartRange]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ranges) { range in
                let isSelected = vm.chartRange == range
                Button {
                    vm.selectChartRange(range, currency: SettingsCurrency.current)
                } label: {
                    Text(range.title)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(isSelected ? Theme.colors.textPrimary : Theme.colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(isSelected ? Theme.colors.bgSurface2 : Color.clear)
                        .clipShape(Theme.radius.pill.shape)
                        // The pill is `maxWidth: .infinity` but an unselected one
                        // fills with `Color.clear`, so without an explicit content
                        // shape the tap area collapses to the glyphs and most of
                        // the button is dead — worse the wider the screen, and it
                        // only afflicts the UNSELECTED pills, which are precisely
                        // the ones being reached for.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
