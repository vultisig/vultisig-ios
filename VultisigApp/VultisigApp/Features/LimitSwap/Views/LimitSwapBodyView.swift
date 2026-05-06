//
//  LimitSwapBodyView.swift
//  VultisigApp
//

import BigInt
import SwiftUI

/// Limit-swap body content — renders inside `SwapCryptoView` when the
/// SegmentedControl is set to Limit. Uniswap-style flat layout: full
/// asset swap-form (Sell + middle button + Buy) on top, editable
/// target-price card below it, then expiry pills, then the place-order
/// CTA. No collapse/expand — every input is visible at once.
struct LimitSwapBodyView: View {

    @Bindable var vm: LimitSwapFormViewModel
    let fromCoin: Coin
    let toCoin: Coin

    @State private var sourceAmountText: String = ""
    @State private var priceText: String = ""

    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void
    let onSwapAssets: () -> Void
    let onPlaceOrder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    LimitPriceCard(
                        vm: vm,
                        priceText: $priceText,
                        onPickFromAsset: onPickFromAsset,
                        onPickToAsset: onPickToAsset
                    )

                    LimitAssetSwapForm(
                        vm: vm,
                        fromCoin: fromCoin,
                        toCoin: toCoin,
                        sourceAmountText: $sourceAmountText,
                        onPickFromAsset: onPickFromAsset,
                        onPickToAsset: onPickToAsset,
                        onSwapAssets: onSwapAssets
                    )

                    LimitExpiryCard(vm: vm)

                    if let warning = vm.displayedWarning {
                        LimitWarningRow(warning: warning)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            PrimaryButton(
                title: "limitSwap.placeOrder".localized,
                action: onPlaceOrder
            )
            .disabled(!isPlaceable)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .onChange(of: sourceAmountText) { _, newText in
            vm.amountChanged(parseAmount(newText, decimals: vm.draft.fromAsset.decimals))
        }
        .onChange(of: priceText) { _, newText in
            let parsed = parsePrice(newText)
            if parsed != vm.draft.targetPrice {
                vm.targetPriceChanged(parsed)
            }
        }
        .onChange(of: vm.draft.targetPrice) { _, newPrice in
            // Sync vm → text only when the local text doesn't already
            // parse to the same Decimal. Preserves trailing "." while
            // typing and reflects preset-pill taps that mutate vm.
            if parsePrice(priceText) != newPrice {
                priceText = newPrice == 0 ? "" : formatPrice(newPrice)
            }
        }
    }

    private var isPlaceable: Bool {
        vm.draft.targetPrice > 0 && vm.draft.sourceAmount > 0
    }

    private func parseAmount(_ text: String, decimals: Int) -> BigInt {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let decimal = Decimal(string: normalized), decimal > 0 else { return 0 }
        var scaled = Decimal()
        var input = decimal
        NSDecimalMultiplyByPowerOf10(&scaled, &input, Int16(decimals), .down)
        var truncated = Decimal()
        NSDecimalRound(&truncated, &scaled, 0, .down)
        return BigInt(NSDecimalNumber(decimal: truncated).stringValue) ?? 0
    }

    private func parsePrice(_ text: String) -> Decimal {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized) ?? 0
    }

    private func formatPrice(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }
}

// MARK: - Asset swap form (Sell + middle swap button + Buy)
//
// Inner content of the FormExpandableSection's expanded state. The section
// header (title + chevron + collapsed-state value display + checkmark +
// pencil) is provided by FormExpandableSection itself.

private struct LimitAssetSwapForm: View {

    @Bindable var vm: LimitSwapFormViewModel
    let fromCoin: Coin
    let toCoin: Coin
    @Binding var sourceAmountText: String
    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void
    let onSwapAssets: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                LimitAssetRow(
                    kind: .sell,
                    coin: fromCoin,
                    asset: vm.draft.fromAsset,
                    amountText: $sourceAmountText,
                    amountIsEditable: true,
                    computedAmount: nil,
                    usdPricePerUnit: Decimal(fromCoin.price),
                    onPickAsset: onPickFromAsset
                )

                LimitAssetRow(
                    kind: .buy,
                    coin: toCoin,
                    asset: vm.draft.toAsset,
                    amountText: .constant(formattedBuyAmount),
                    amountIsEditable: false,
                    computedAmount: buyAmountDecimal,
                    usdPricePerUnit: vm.targetUsdPricePerUnit,
                    onPickAsset: onPickToAsset
                )
            }

            Button(action: onSwapAssets) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Theme.colors.primaryAccent3)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(7)
                    .background(Theme.colors.bgPrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25.5)
                            .stroke(Theme.colors.borderLight, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 25.5))
            }
            .buttonStyle(.plain)
        }
    }

    /// Buy amount = sourceAmount × targetPrice (when target is set).
    /// `nil` if not yet computable, in which case the row shows "0".
    private var buyAmountDecimal: Decimal? {
        let sourceAmount = vm.draft.sourceAmount
        let targetPrice = vm.draft.targetPrice
        guard sourceAmount > 0, targetPrice > 0 else { return nil }
        let sourceDecimal = Decimal(string: sourceAmount.description) ?? 0
        let sourceNatural = sourceDecimal / pow(10, vm.draft.fromAsset.decimals)
        return sourceNatural * targetPrice
    }

    private var formattedBuyAmount: String {
        guard let amount = buyAmountDecimal else { return "0" }
        return NSDecimalNumber(decimal: amount).stringValue
    }
}

// MARK: - Single asset row (chain header + coin pill + amount field)

private enum LimitAssetRowKind {
    case sell
    case buy

    var labelKey: String {
        self == .sell ? "limitSwap.sell" : "limitSwap.buy"
    }

    var cornerRadii: RectangleCornerRadii {
        // Mirrors the Figma — Sell rounded top-heavy, Buy bottom-heavy.
        switch self {
        case .sell:
            return .init(topLeading: 24, bottomLeading: 12, bottomTrailing: 12, topTrailing: 24)
        case .buy:
            return .init(topLeading: 12, bottomLeading: 24, bottomTrailing: 24, topTrailing: 12)
        }
    }
}

private struct LimitAssetRow: View {

    let kind: LimitAssetRowKind
    let coin: Coin
    let asset: LimitSwapAsset
    @Binding var amountText: String
    let amountIsEditable: Bool
    let computedAmount: Decimal?
    let usdPricePerUnit: Decimal
    let onPickAsset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: label + chain selector (left) | balance (right)
            HStack {
                HStack(spacing: 6) {
                    Text(kind.labelKey.localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)

                    Button(action: onPickAsset) {
                        HStack(spacing: 4) {
                            if !asset.chainLogo.isEmpty {
                                AsyncImageView(
                                    logo: asset.chainLogo,
                                    size: CGSize(width: 16, height: 16),
                                    ticker: asset.chain.ticker,
                                    tokenChainLogo: nil
                                )
                            }
                            Text(asset.chain.name)
                                .font(Theme.fonts.caption12)
                                .foregroundStyle(Theme.colors.textPrimary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.colors.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if kind == .sell {
                    Text("\(coin.balanceString) \(coin.ticker)")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                }
            }

            // Bottom: coin pill (left) | amount + fiat (right)
            HStack(alignment: .center) {
                Button(action: onPickAsset) {
                    HStack(spacing: 8) {
                        if !asset.logo.isEmpty {
                            AsyncImageView(
                                logo: asset.logo,
                                size: CGSize(width: 36, height: 36),
                                ticker: asset.ticker,
                                tokenChainLogo: asset.chainLogo
                            )
                        }
                        Text(asset.ticker)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 12)
                    .padding(.vertical, 6)
                    .background(Theme.colors.bgSurface2)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    if amountIsEditable {
                        TextField("0", text: $amountText)
                            .font(Theme.fonts.title2)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    } else {
                        Text(amountText)
                            .font(Theme.fonts.title2)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }

                    Text(fiatLine)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(cornerRadii: kind.cornerRadii)
                .fill(Color.clear)
                .overlay(
                    UnevenRoundedRectangle(cornerRadii: kind.cornerRadii)
                        .stroke(Theme.colors.borderLight, lineWidth: 1)
                )
        )
    }

    private var fiatLine: String {
        let amount = effectiveAmount
        guard usdPricePerUnit > 0, amount > 0 else { return "$0.00" }
        let usd = amount * usdPricePerUnit
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        let value = formatter.string(from: NSDecimalNumber(decimal: usd)) ?? "0.00"
        return "$\(value)"
    }

    private var effectiveAmount: Decimal {
        if let computedAmount {
            return computedAmount
        }
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized) ?? 0
    }
}

// MARK: - Limit price card (Uniswap-style)
//
// Header: "When 1 [icon] <TICKER> is worth" (LimitExecuteWhenTitle) — the
// icon + ticker are tappable and open the from-asset picker. Body: large
// editable price input on the left, target [icon] TICKER button on the
// right (tappable → to-asset picker). Below: market reference rate.
// Below: preset pills (the Market pill is dynamic — see LimitPresetPills).

private struct LimitPriceCard: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Binding var priceText: String
    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LimitExecuteWhenTitle(
                asset: vm.draft.fromAsset,
                onTapAsset: onPickFromAsset
            )

            HStack(alignment: .center) {
                TextField("0", text: $priceText)
                    .font(Theme.fonts.priceTitle1)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif

                Spacer(minLength: 8)

                Button(action: onPickToAsset) {
                    HStack(spacing: 6) {
                        if !vm.draft.toAsset.logo.isEmpty {
                            AsyncImageView(
                                logo: vm.draft.toAsset.logo,
                                size: CGSize(width: 20, height: 20),
                                ticker: vm.draft.toAsset.ticker,
                                tokenChainLogo: vm.draft.toAsset.chainLogo
                            )
                        }
                        Text(vm.draft.toAsset.ticker)
                            .font(Theme.fonts.priceBodyL)
                            .foregroundStyle(Theme.colors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }

            LimitPresetPills(vm: vm)
        }
        .padding(16)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preset pills
//
// Layout uses a custom `LimitPillFlow` so pills wrap to a second row when
// the dynamic Market pill's content (e.g. "+12.5% ✕") is too wide for one
// row. The +1% / +5% / +10% pills are always static and just call
// `selectPresetPct(pct)`. The Market pill is dynamic but only after a
// *manual* edit — when any preset is the live source (`vm.lastPresetPct
// != nil`), it stays static "Market". Tapping any pill dismisses the
// keyboard so the keyboard doesn't linger after a preset selection.

private struct LimitPresetPills: View {

    @Bindable var vm: LimitSwapFormViewModel

    var body: some View {
        LimitPillFlow(spacing: 6) {
            marketPill
            staticPill(titleKey: "limitSwap.preset.plus1", pct: 1)
            staticPill(titleKey: "limitSwap.preset.plus5", pct: 5)
            staticPill(titleKey: "limitSwap.preset.plus10", pct: 10)
        }
    }

    @ViewBuilder
    private var marketPill: some View {
        let rounded = roundedPctFromMarket
        // Render statically when *any* preset is the live source (including
        // Market preset) OR when there's effectively no delta from market.
        // The dynamic state only kicks in after the user manually edits the
        // price (which sets `vm.lastPresetPct = nil`).
        let renderStatic = vm.lastPresetPct != nil || rounded == 0
        Button {
            dismissKeyboard()
            vm.selectPresetPct(0)
        } label: {
            HStack(spacing: 4) {
                if renderStatic {
                    Text("limitSwap.preset.market".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)
                } else {
                    Text(formatRoundedPct(rounded))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 100)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(vm.marketPriceRef == nil)
    }

    private func staticPill(titleKey: String, pct: Int) -> some View {
        Button {
            dismissKeyboard()
            vm.selectPresetPct(pct)
        } label: {
            Text(titleKey.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 100)
                        .stroke(Theme.colors.borderLight, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(vm.marketPriceRef == nil)
    }

    /// Rounds `vm.pctFromMarket` to the nearest 0.5%. Returns 0 when no
    /// market reference is loaded yet, when target price is 0, or when the
    /// actual pct rounds to 0 (i.e. |pct| < 0.25%).
    private var roundedPctFromMarket: Decimal {
        guard vm.marketPriceRef != nil, vm.draft.targetPrice > 0 else { return 0 }
        var doubled = vm.pctFromMarket * 2
        var rounded = Decimal()
        NSDecimalRound(&rounded, &doubled, 0, .plain)
        return rounded / 2
    }

    private func formatRoundedPct(_ pct: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        let value = formatter.string(from: NSDecimalNumber(decimal: pct)) ?? "0"
        return "\(value)%"
    }

    private func dismissKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        #endif
    }
}

// MARK: - Pill flow layout
//
// Wraps subviews to a second row when content overflows the available
// width. Each child is sized by its own intrinsic content (so the dynamic
// Market pill grows when its label becomes "+12.5% ✕"); other pills can
// drop to the next line instead of getting cropped.

private struct LimitPillFlow: Layout {

    let spacing: CGFloat

    init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = arrange(subviews: subviews, in: width)
        let totalHeight = lines.map(\.height).reduce(0, +)
            + CGFloat(max(0, lines.count - 1)) * spacing
        let widestLine = lines.map(\.width).max() ?? 0
        return CGSize(width: widestLine, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = arrange(subviews: subviews, in: bounds.width)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = [Line()]
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            let extraSpacing: CGFloat = lines[lines.count - 1].indices.isEmpty ? 0 : spacing
            let prospectiveWidth = lines[lines.count - 1].width + extraSpacing + size.width
            if prospectiveWidth > maxWidth, !lines[lines.count - 1].indices.isEmpty {
                var newLine = Line()
                newLine.indices = [i]
                newLine.width = size.width
                newLine.height = size.height
                lines.append(newLine)
            } else {
                lines[lines.count - 1].indices.append(i)
                lines[lines.count - 1].width = prospectiveWidth
                lines[lines.count - 1].height = max(lines[lines.count - 1].height, size.height)
            }
        }
        return lines
    }
}

// MARK: - Expiry card

private struct LimitExpiryCard: View {

    @Bindable var vm: LimitSwapFormViewModel

    var body: some View {
        HStack {
            Text("limitSwap.expiry".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Spacer()

            HStack(spacing: 6) {
                pill(titleKey: "limitSwap.expiry.12h", hours: 12)
                pill(titleKey: "limitSwap.expiry.24h", hours: 24)
                pill(titleKey: "limitSwap.expiry.3d", hours: 72)
            }
        }
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func pill(titleKey: String, hours: Int) -> some View {
        let isSelected = vm.draft.expiryHours == hours
        return Button {
            vm.selectExpiryHours(hours)
        } label: {
            Text(titleKey.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Theme.colors.bgSurface2 : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 100)
                        .stroke(Theme.colors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 100))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Execute When section title
//
// "When 1 [icon] <TICKER> is worth" — the icon + ticker reference the
// source asset (the thing being sold) and are tappable as a single button
// that opens the from-asset picker. Ticker is rendered in `textSecondary`
// to highlight it against the surrounding `textPrimary` header text.

private struct LimitExecuteWhenTitle: View {

    let asset: LimitSwapAsset
    let onTapAsset: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("limitSwap.executeWhen.headerWhenOne".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Button(action: onTapAsset) {
                HStack(spacing: 4) {
                    if !asset.logo.isEmpty {
                        AsyncImageView(
                            logo: asset.logo,
                            size: CGSize(width: 16, height: 16),
                            ticker: asset.ticker,
                            tokenChainLogo: asset.chainLogo
                        )
                    }
                    Text(asset.ticker)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
            }
            .buttonStyle(.plain)

            Text("limitSwap.executeWhen.headerIsWorth".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }
}

// MARK: - Warning row

private struct LimitWarningRow: View {

    let warning: LimitSwapWarning

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.colors.alertWarning)

            Text(messageKey.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var messageKey: String {
        switch warning {
        case .priceAtOrBelowMarket:
            return "limitSwap.warning.priceAtOrBelowMarket"
        case .priceFarAboveMarket:
            return "limitSwap.warning.priceFarAboveMarket"
        }
    }
}
