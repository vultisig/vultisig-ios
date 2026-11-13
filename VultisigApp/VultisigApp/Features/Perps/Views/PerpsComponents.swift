//
//  PerpsComponents.swift
//  VultisigApp
//
//  Perps building blocks, "Phantom-simple": a centered amount, cards
//  of plain rows, market rows, the timeframe picker and the price chart.
//

import Charts
import SwiftUI

/// The big centered amount the ticket and money sheets lead with. Typed on
/// `PerpsKeypad` (always "."), shown grouped: never the system decimal pad,
/// which shows "," in comma-decimal locales.
struct PerpsAmountInput: View {
    let text: String
    var prefix: String = "$"
    var suffix: String = ""
    var isFocused = false
    var accessibilityID = "perpsAmountInput"
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if !prefix.isEmpty {
                    Text(prefix)
                        .font(Theme.fonts.priceLargeTitle)
                        .foregroundStyle(text.isEmpty ? Theme.colors.textTertiary : Theme.colors.textPrimary)
                }
                Text(text.isEmpty ? "0" : PerpsInput.grouped(text))
                    .font(Theme.fonts.priceLargeTitle)
                    .monospacedDigit()
                    .foregroundStyle(text.isEmpty ? Theme.colors.textTertiary : Theme.colors.textPrimary)
                if isFocused {
                    PerpsCaret(height: 30)
                }
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(Theme.fonts.title2)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }
}

/// The insertion point of a keypad field.
struct PerpsCaret: View {
    let height: CGFloat

    var body: some View {
        Capsule()
            .fill(Theme.colors.primaryAccent4)
            .frame(width: 2, height: height)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
    }
}

/// rhythm, on the app's tokens: 20pt margins, 16pt card padding,
/// 24pt between sections, 12pt between related elements.
enum PerpsLayout {
    static let margin: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let section: CGFloat = 24
    static let related: CGFloat = 12
}

/// A sheet's title: 17pt, centered (closest token: title3).
struct PerpsSheetTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.fonts.title3)
            .foregroundStyle(Theme.colors.textPrimary)
            .frame(maxWidth: .infinity)
    }
}

/// chips: equal-width capsules on the surface colour, the selected
/// one lifted and outlined in blue. Used for 25% / 50% / All and Add / Remove.
struct PerpsChipPicker<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    var isEnabled: (Option) -> Bool = { _ in true }
    var accessibilityPrefix = "perpsChip"

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                let enabled = isEnabled(option)
                Button { selection = option } label: {
                    Text(title(option))
                        .font(Theme.fonts.subtitle)
                        .foregroundStyle(isSelected ? Theme.colors.textPrimary : Theme.colors.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Capsule().fill(isSelected ? Theme.colors.bgSurface2 : Theme.colors.bgSurface1))
                        .overlay(Capsule().stroke(isSelected ? Theme.colors.primaryAccent3 : Theme.colors.borderLight, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.35)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("\(accessibilityPrefix)-\(title(option))")
            }
        }
    }
}

/// Round back button for a sheet's second page, the same size as the sheet close button.
struct PerpsSheetBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(.chevronLeft, color: Theme.colors.textPrimary, size: 18)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.colors.bgSheetControl))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("perpsBack".localized)
    }
}

/// Round × that dismisses a sheet, the twin of `PerpsSheetBackButton`.
struct PerpsSheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(.xmark, color: Theme.colors.textSecondary, size: 16)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.colors.bgSheetControl))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("close".localized)
    }
}

/// A rounded card holding rows separated by hairlines.
struct PerpsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(Theme.radius.lg.shape.fill(Theme.colors.bgSurface1))
    }
}

/// Label (and optional subtitle) on the left, value and accessory on the right.
struct PerpsRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    var value: String?
    var valueColor: Color = Theme.colors.textPrimary
    var showsDivider = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider { Separator(color: Theme.colors.borderLight, opacity: 1) }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.fonts.subtitle)
                        .foregroundStyle(Theme.colors.textSecondary)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.fonts.footnote)
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(Theme.fonts.priceBodyS)
                        .monospacedDigit()
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                accessory()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }
}

extension PerpsRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, value: String?, valueColor: Color = Theme.colors.textPrimary, showsDivider: Bool = false) {
        self.init(title: title, subtitle: subtitle, value: value, valueColor: valueColor, showsDivider: showsDivider) { EmptyView() }
    }
}

struct PerpsChevron: View {
    var body: some View { Icon(.chevronRightSmall, color: Theme.colors.textTertiary, size: 16) }
}

/// "BTC-USD · 40×" on the left, price and the 24h move on the right.
struct PerpsMarketListRow: View {
    let market: PerpsMarket

    var body: some View {
        HStack(spacing: 12) {
            PerpsCoinBadge(coin: market.coin, size: 32)
            Text(String(format: "perpsPairName".localized, market.coin))
                .font(Theme.fonts.subtitle)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(PerpsFormat.price(market.markPrice))
                    .font(Theme.fonts.priceBodyS)
                    .monospacedDigit()
                    .foregroundStyle(Theme.colors.textPrimary)
                Text(PerpsFormat.percent(market.change24h))
                    .font(Theme.fonts.priceCaption)
                    .foregroundStyle(market.change24h >= 0 ? Theme.colors.alertSuccess : Theme.colors.alertError)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct PerpsSectionHeader: View {
    let title: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            if let action {
                Button(action: action.run) {
                    Text(action.title)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.primaryAccent4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct PerpsTimeframePicker: View {
    let selected: PerpsTimeframe
    let onSelect: (PerpsTimeframe) -> Void

    var body: some View {
        HStack {
            ForEach(PerpsTimeframe.allCases, id: \.self) { timeframe in
                Button { onSelect(timeframe) } label: {
                    Text(timeframe.rawValue)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(timeframe == selected ? Theme.colors.textPrimary : Theme.colors.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(timeframe == selected ? Theme.colors.bgSurface2 : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("perpsTimeframe-\(timeframe.rawValue)")
                if timeframe != PerpsTimeframe.allCases.last { Spacer(minLength: 0) }
            }
        }
    }
}

/// A price level drawn across the chart (entry, liquidation).
struct PerpsLevel: Identifiable, Equatable {
    let title: String
    let price: Decimal
    let color: Color
    /// Always widens the chart to stay visible (the entry on a position);
    /// other levels only widen it when they sit near the move.
    var isPinned = false

    var id: String { title }
    var value: Double { NSDecimalNumber(decimal: price).doubleValue }
}

/// Native Swift Charts line, tinted by direction, with optional level lines.
struct PerpsPriceChart: View {
    let points: [MarketChartPoint]
    var levels: [PerpsLevel] = []
    var height: CGFloat = 220
    /// Overrides the up/down colour: a position's chart follows its P&L, not the price move.
    var tint: Color?

    private var isUp: Bool { (points.last?.price ?? 0) >= (points.first?.price ?? 0) }

    private var domain: ClosedRange<Double> {
        let prices = points.map(\.price)
        guard let low = prices.min(), let high = prices.max(), high > 0 else { return 0...1 }
        // A level far outside the move (a distant liquidation) would flatten
        // the line, so only levels within 3x the visible range widen it.
        let span = max(high - low, high * 0.01)
        let near = levels.filter { $0.isPinned || ($0.value >= low - 3 * span && $0.value <= high + 3 * span) }.map(\.value)
        let minValue = min(low, near.min() ?? low)
        let maxValue = max(high, near.max() ?? high)
        let pad = (maxValue - minValue) * 0.1
        return (minValue - pad)...(maxValue + pad)
    }

    var body: some View {
        let domain = domain
        let tint = tint ?? (isUp ? Theme.colors.alertSuccess : Theme.colors.alertError)
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                AreaMark(x: .value("t", point.date), yStart: .value("low", domain.lowerBound), yEnd: .value("p", point.price))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", point.date), y: .value("p", point.price))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            ForEach(levels.filter { domain.contains($0.value) }) { level in
                RuleMark(y: .value(level.title, level.value))
                    .foregroundStyle(level.color.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: placement(for: level, domain: domain).0,
                                alignment: placement(for: level, domain: domain).1, spacing: 3) {
                        levelPill(level)
                    }
            }
        }
        .chartYScale(domain: domain)
        // Room for the end dot inside the chart's own frame.
        .chartXScale(range: .plotDimension(endPadding: 6))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            // The current price: a dot where the line ends, drawn over the
            // plot so the chart's edge never clips it.
            GeometryReader { geometry in
                if let last = points.last, let plotFrame = proxy.plotFrame,
                   let x = proxy.position(forX: last.date), let y = proxy.position(forY: last.price) {
                    let origin = geometry[plotFrame].origin
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                        .position(x: origin.x + x, y: origin.y + y)
                }
            }
        }
        .frame(height: height)
        .accessibilityIdentifier("perpsPriceChart")
    }

    /// Where a level's pill goes: the first corner (right then left, above then
    /// below the line) where the series never enters the pill's band, so the
    /// line never runs through a label. Falls back to the side away from the
    /// latest price.
    private func placement(for level: PerpsLevel, domain: ClosedRange<Double>) -> (AnnotationPosition, Alignment) {
        let prices = points.map(\.price)
        guard !prices.isEmpty, height > 0 else { return (.top, .trailing) }
        // The pill is about 20pt tall and 40% of the width.
        let band = (domain.upperBound - domain.lowerBound) * 22 / Double(height)
        let regionCount = max(1, prices.count * 2 / 5)
        let regions: [(Alignment, ArraySlice<Double>)] = [(.trailing, prices.suffix(regionCount)), (.leading, prices.prefix(regionCount))]
        for (alignment, region) in regions {
            if region.allSatisfy({ $0 < level.value || $0 > level.value + band }) { return (.top, alignment) }
            if region.allSatisfy({ $0 > level.value || $0 < level.value - band }) { return (.bottom, alignment) }
        }
        return ((prices.last ?? level.value) >= level.value ? .bottom : .top, .trailing)
    }

    /// "Entry $66,975" in a small pill.
    private func levelPill(_ level: PerpsLevel) -> some View {
        Text("\(level.title) \(PerpsFormat.price(level.price))")
            .font(Theme.fonts.caption10)
            .monospacedDigit()
            .foregroundStyle(level.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.colors.bgPrimary.opacity(0.85)))
            .overlay(Capsule().stroke(level.color.opacity(0.35), lineWidth: 1))
    }
}

/// Sizes the sheet to its content instead of a fixed or full-height detent.
private struct PerpsFitDetent: ViewModifier {
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .sheetStyle(detents: [.height(height + 16)])
    }
}

extension View {
    /// 20pt side margins on perps screens; charts bleed back to the edges.
    /// Perps screens: the shared margins on the app's gradient background (the
    /// blue glow at the top, as on the wallet home).
    func perpsScreenMargins() -> some View {
        screenEdgeInsets(ScreenEdgeInsets(leading: PerpsLayout.margin, trailing: PerpsLayout.margin))
            .screenBackground(.gradient)
    }

    /// compact header: back button, then a small logo and the symbol centered.
    func perpsCompactHeader(coin: String) -> some View {
        screenToolbar {
            CustomToolbarItem(placement: .center, hideSharedBackground: true) {
                HStack(spacing: 8) {
                    PerpsCoinBadge(coin: coin, size: 24)
                    Text(coin)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
            }
        }
    }

    /// Sheet chrome shared by the perps sheets: gutters, keyboard Done, and a
    /// detent measured from the content so the CTA sits right under it.
    func perpsSheetChrome() -> some View {
        self
            .padding(.horizontal, PerpsLayout.margin)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .modifier(PerpsFitDetent())
        #if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    KeyboardDoneButton { hideKeyboard() }
                }
            }
        #endif
    }
}
