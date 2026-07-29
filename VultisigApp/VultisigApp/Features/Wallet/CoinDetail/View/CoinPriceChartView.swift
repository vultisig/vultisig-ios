//
//  CoinPriceChartView.swift
//  VultisigApp
//
//  Price history card on the coin-detail sheet: scrub-aware price header,
//  gradient area chart and the range picker.
//

import Charts
import SwiftUI

struct CoinPriceChartView: View {
    let chart: MarketChart?
    let range: MarketChartRange
    let isLoading: Bool
    let spotPrice: Decimal
    let changeFraction: Double?
    let isPositive: Bool
    var onSelectRange: (MarketChartRange) -> Void

    @State private var scrubbedDate: Date?

    private static let chartHeight: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            chartArea
            CoinChartRangePicker(selected: range, onSelect: onSelectRange)
        }
        .padding(16)
        .commonListContainer()
        .onChange(of: range) { _, _ in
            // The old scrub position means nothing on a different window.
            scrubbedDate = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayedPrice)
                    .font(Theme.fonts.priceTitle2)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.18), value: displayedPrice)

                // Reserved height: the scrub label appears and disappears on
                // every drag, and a header that changes height would make the
                // chart jump under the finger.
                Text(scrubbedPoint.map { range.formattedScrubDate($0.date) } ?? "")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .frame(height: 16, alignment: .leading)
            }

            Spacer(minLength: 8)

            changeChip
        }
    }

    @ViewBuilder
    private var changeChip: some View {
        if let changeFraction {
            Text(Self.formattedChange(changeFraction))
                .font(Theme.fonts.caption12)
                .foregroundStyle(tint)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Capsule().fill(tint.opacity(0.12)))
                // Dimmed with the line it describes: while the next range
                // loads, the picker already highlights the new window but this
                // percentage still belongs to the old one, and the two must
                // read as one stale group rather than a live figure.
                .opacity(isLoading ? 0.3 : 1)
                .animation(.easeInOut(duration: 0.2), value: isLoading)
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartArea: some View {
        ZStack {
            if let chart {
                series(chart)
                    // The previous window stays on screen, dimmed, while the
                    // next one loads. On its own animation so the fade and the
                    // swap below never drive the same views at once — the flag
                    // and the new series are assigned in the same main-actor
                    // turn, so one shared animation would catch both.
                    .opacity(isLoading ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isLoading)
                    .transition(.chartSwap)
                    // Identity is the series itself, so a new window replaces
                    // the plot instead of updating it in place. Marks are
                    // diffed by array position, so without this a switch to a
                    // window with fewer samples morphs every mark between two
                    // unrelated prices and fades the surplus ones out at their
                    // old coordinates — stale line and fill drawn over the
                    // incoming series.
                    .id(chart)
            } else {
                placeholder
                    .transition(.chartSwap)
            }
        }
        .frame(height: Self.chartHeight)
        // One animation, driving one thing: the swap. Both halves of the
        // transition have to share a curve to stay complementary, and stacking
        // a second `.animation(_:value:)` here would race them — a range switch
        // changes the series and the loading flag together.
        .animation(.easeInOut(duration: 0.35), value: chart)
        .accessibilityLabel("priceChart".localized)
    }

    private func series(_ chart: MarketChart) -> some View {
        let domain = chart.priceDomain

        return Chart {
            // Identified by position, not by timestamp: a duplicated timestamp
            // would silently drop marks, and the view must not depend on the
            // decoder having de-duplicated them.
            ForEach(Array(chart.points.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("date", point.date),
                    yStart: .value("low", domain.lowerBound),
                    yEnd: .value("price", point.price)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(areaGradient)

                LineMark(
                    x: .value("date", point.date),
                    y: .value("price", point.price)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            if let scrubbedPoint {
                RuleMark(x: .value("date", scrubbedPoint.date))
                    .foregroundStyle(Theme.colors.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                PointMark(
                    x: .value("date", scrubbedPoint.date),
                    y: .value("price", scrubbedPoint.price)
                )
                .symbolSize(70)
                .foregroundStyle(tint)
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
#if os(iOS)
        // Touch: press-and-drag along the chart.
        .chartXSelection(value: $scrubbedDate)
        .sensoryFeedback(.selection, trigger: scrubbedPoint?.date)
#else
        // Pointer: scrub on hover. `chartXSelection` is drag-driven, which on a
        // Mac means holding the mouse button down to read a chart — the
        // pointer is already there, so tracking it is the native gesture.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let plotOrigin = geometry[plotFrame].origin
                            scrubbedDate = proxy.value(atX: location.x - plotOrigin.x)
                        case .ended:
                            scrubbedDate = nil
                        }
                    }
            }
        }
#endif
    }

    private var placeholder: some View {
        Chart {
            ForEach(Array(Self.placeholderPoints.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("date", point.date),
                    yStart: .value("low", 0),
                    yEnd: .value("price", point.price)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.colors.borderLight.opacity(0.7), Theme.colors.borderLight.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("date", point.date),
                    y: .value("price", point.price)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Theme.colors.borderLight)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .redacted(reason: .placeholder)
    }

    // MARK: - Derived

    private var tint: Color {
        isPositive ? Theme.colors.alertSuccess : Theme.colors.alertError
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.3), tint.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Sample nearest the scrub position. Linear over at most
    /// `MarketChartLimits.maximumRenderedPoints` samples, which is why the
    /// series is thinned before it reaches the view.
    private var scrubbedPoint: MarketChartPoint? {
        guard let scrubbedDate, let points = chart?.points, !points.isEmpty else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(scrubbedDate)) < abs($1.date.timeIntervalSince(scrubbedDate))
        }
    }

    /// The scrubbed sample while dragging, otherwise the live spot price.
    ///
    /// Spot rather than the series' last sample: the header should agree with
    /// the price the rest of the app shows. The series can lag it by a few
    /// minutes, which is normal for a chart's right edge.
    private var displayedPrice: String {
        if let scrubbedPoint {
            return Decimal(scrubbedPoint.price).formatToFiatPrice()
        }
        return spotPrice.formatToFiatPrice()
    }

    private static func formattedChange(_ fraction: Double) -> String {
        let percentage = Decimal(fraction * 100)
        let sign = percentage < 0 ? "" : "+"
        return "\(sign)\(percentage.formatToDecimal(digits: 2))%"
    }

    /// Fixed shape for the loading state. A recognisable price-like line reads
    /// as "a chart is coming" where a flat bar reads as "there is no data".
    private static let placeholderPoints: [MarketChartPoint] = {
        let shape: [Double] = [0.30, 0.46, 0.38, 0.55, 0.48, 0.68, 0.58, 0.74, 0.66, 0.85]
        return shape.enumerated().map { index, value in
            MarketChartPoint(
                date: Date(timeIntervalSince1970: TimeInterval(index) * 3600),
                price: value
            )
        }
    }()
}

/// Horizontal reveal: `progress` is the fraction of the plot's width that stays
/// visible, measured from `edge`.
///
/// A mask rather than an opacity fade, so the line reads as being *drawn*. And
/// because the identity state is a full-width mask, the chart is only ever
/// *more* visible than the animation asks for — it can never be stuck hidden.
private struct ChartWipe: ViewModifier, Animatable {
    var progress: CGFloat
    var edge: HorizontalAlignment

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { geometry in
                Rectangle()
                    .frame(width: geometry.size.width * max(0, min(1, progress)))
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: Alignment(horizontal: edge, vertical: .center)
                    )
            }
        }
    }
}

private extension AnyTransition {

    /// How one series gives way to the next: the incoming one sweeps in from
    /// the leading edge while the outgoing one retracts ahead of it.
    ///
    /// The two masks are complements of each other on the same curve, so they
    /// tile the plot exactly — every column holds one series or the other,
    /// never both and never neither. A plain cross-fade instead draws the two
    /// price lines over each other for the length of the fade, and staging the
    /// fade before the wipe leaves the card empty in between; both were
    /// rendered and compared frame by frame, and both read as a glitch.
    static var chartSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: ChartWipe(progress: 0, edge: .leading),
                identity: ChartWipe(progress: 1, edge: .leading)
            ),
            removal: .modifier(
                active: ChartWipe(progress: 0, edge: .trailing),
                identity: ChartWipe(progress: 1, edge: .trailing)
            )
        )
    }
}

#Preview {
    let points = (0..<60).map { index in
        MarketChartPoint(
            date: Date(timeIntervalSince1970: TimeInterval(index) * 300),
            price: 100 + sin(Double(index) / 6) * 8 + Double(index) / 4
        )
    }

    return CoinPriceChartView(
        chart: MarketChart(points: points),
        range: .day,
        isLoading: false,
        spotPrice: 118,
        changeFraction: 0.0421,
        isPositive: true,
        onSelectRange: { _ in }
    )
    .padding()
    .background(Theme.colors.bgPrimary)
}
