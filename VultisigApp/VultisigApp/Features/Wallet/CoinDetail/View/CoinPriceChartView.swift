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

    /// Where along the series the finger is, in sample positions rather than in
    /// time — the plot's x axis is the sample's index.
    @State private var scrubbedPosition: Double?

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
            scrubbedPosition = nil
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
                .opacity(isDimmed ? 0.3 : 1)
                .animation(.easeInOut(duration: 0.2), value: isDimmed)
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartArea: some View {
        ZStack {
            if let chart {
                series(chart)
                    .transition(.chartSwap)
            } else {
                placeholder
                    .transition(.chartSwap)
            }
        }
        .frame(height: Self.chartHeight)
        // One animation, driving one thing: the series on screen. A new window
        // updates the marks in place, so Charts interpolates the line from the
        // old shape into the new one; the transition only runs on the genuine
        // insertion and removal, which is the placeholder giving way to the
        // first series.
        .animation(.easeInOut(duration: 0.35), value: chart)
        // The previous window stays readable, dimmed, while the next loads. On
        // its own modifier *outside* the swap animation: the flag and the new
        // series are published in the same main-actor turn, and one shared
        // animation would make the dim and the morph fight for the same views.
        .opacity(isDimmed ? 0.3 : 1)
        .animation(.easeInOut(duration: 0.2), value: isDimmed)
        .accessibilityLabel("priceChart".localized)
    }

    /// The plot's x is the sample's *position* in the series, not its
    /// timestamp.
    ///
    /// Every window arrives resampled to the same number of samples, so index
    /// `i` is the same relative point of the window whichever range is on
    /// screen. Charts diffs marks by array position, so switching range moves
    /// each mark from one price to the next and the line grows into its new
    /// shape — nothing is inserted, nothing is removed, and no mark is left
    /// fading at coordinates that belong to the previous window. The x scale is
    /// then fixed rather than inferred from the dates, so only the prices
    /// travel; the timestamps stay in `points`, where the scrub reads them.
    private func series(_ chart: MarketChart) -> some View {
        let domain = chart.priceDomain
        let scrubbed = scrubbedIndex(in: chart)

        return Chart {
            ForEach(Array(chart.points.enumerated()), id: \.offset) { index, point in
                AreaMark(
                    x: .value("position", Double(index)),
                    yStart: .value("low", domain.lowerBound),
                    yEnd: .value("price", point.price)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(areaGradient)

                LineMark(
                    x: .value("position", Double(index)),
                    y: .value("price", point.price)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            if let scrubbed {
                RuleMark(x: .value("position", Double(scrubbed)))
                    .foregroundStyle(Theme.colors.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                PointMark(
                    x: .value("position", Double(scrubbed)),
                    y: .value("price", chart.points[scrubbed].price)
                )
                .symbolSize(70)
                .foregroundStyle(tint)
            }
        }
        .chartXScale(domain: 0...Double(max(1, chart.points.count - 1)))
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
#if os(iOS)
        // Touch: press-and-drag along the chart.
        .chartXSelection(value: $scrubbedPosition)
        .sensoryFeedback(.selection, trigger: scrubbed)
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
                            scrubbedPosition = proxy.value(
                                atX: location.x - plotOrigin.x,
                                as: Double.self
                            )
                        case .ended:
                            scrubbedPosition = nil
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

    /// Whether the series on screen belongs to the range the picker shows. It
    /// is dimmed while it does not, and only then — the placeholder is already
    /// a loading state and fading it further reads as a failure.
    private var isDimmed: Bool {
        chart != nil && isLoading
    }

    /// Which sample the scrub sits on. The plot's x *is* the sample's position,
    /// so the touch rounds straight to an index instead of searching the series
    /// for the nearest timestamp.
    private func scrubbedIndex(in chart: MarketChart) -> Int? {
        scrubbedPosition.flatMap(chart.index(atPosition:))
    }

    /// The scrubbed sample itself — its real timestamp and price, whatever the
    /// plot's own units are.
    private var scrubbedPoint: MarketChartPoint? {
        guard let chart, let index = scrubbedIndex(in: chart) else { return nil }
        return chart.points[index]
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

    /// How the plot arrives and leaves: it is drawn in from the leading edge,
    /// and retracts to the trailing edge on the way out.
    ///
    /// This runs on the one genuine insertion — the loading placeholder giving
    /// way to the first real series — where the two masks are complements on
    /// the same curve and tile the plot exactly: every column holds one of them
    /// or the other, never both and never neither. Switching *between* windows
    /// is not an insertion; that updates the marks in place so the line morphs.
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
