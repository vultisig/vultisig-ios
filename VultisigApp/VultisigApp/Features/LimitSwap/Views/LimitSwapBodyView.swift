//
//  LimitSwapBodyView.swift
//  VultisigApp
//

import BigInt
import SwiftUI

/// Limit-swap body content — renders inside `SwapCryptoView` when the
/// SegmentedControl is set to Limit. Matches Figma `74341-118736`: a two-section
/// **accordion** (Execute when / Asset, one open at a time) with a quote-refresh
/// countdown in the header and the Place-Order CTA pinned to the bottom.
///
/// All business logic lives in `LimitSwapFormViewModel`; this view is
/// declarative. The price field always edits `draft.targetPrice` in the target
/// asset's terms (the value the signed memo's LIM is derived from) — the $/asset
/// toggle only changes which representation is emphasized, never how the price is
/// stored, so the memo math is never at risk.
struct LimitSwapBodyView: View {

    enum FocusedSection: Hashable {
        case executeWhen
        case asset
    }

    @Bindable var vm: LimitSwapFormViewModel
    let fromCoin: Coin
    let toCoin: Coin

    /// Which section is open on first launch. The Figma first-launch state
    /// (screen 1) is the Asset section expanded; tapping "Execute when"
    /// collapses Asset into its compact summary and expands the price card.
    /// The section is actually opened by `.onLoad` committing this into
    /// `focusedSection` (see below).
    var initialFocusedSection: FocusedSection = .asset

    /// `nil` on frame 0, then seeded from `initialFocusedSection` in `.onLoad`.
    /// Starting at `nil` (rather than a fixed section) is what lets each
    /// `FormExpandableSection`'s `onChange(of: focusedField)` observe the
    /// transition and drive its open animation — the same nil→onLoad focus
    /// pattern the Send/Bond expandable forms use.
    @State private var focusedSection: FocusedSection?
    @State private var sourceAmountText: String = ""
    @State private var priceText: String = ""

    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void
    let onSwapAssets: () -> Void
    let onPlaceOrder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            QuoteRefreshTimerRow(vm: vm)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    FormExpandableSection(
                        title: "limitSwap.executeWhen".localized,
                        isValid: false,
                        value: "",
                        showValue: false,
                        focusedField: $focusedSection,
                        focusedFieldEquals: .executeWhen,
                        cornerRadius: 24,
                        onExpand: { isExpanded in
                            focusedSection = isExpanded ? .executeWhen : nil
                        },
                        content: {
                            LimitExecuteWhenContent(
                                vm: vm,
                                priceText: $priceText,
                                onPickToAsset: onPickToAsset
                            )
                        }
                    )

                    FormExpandableSection(
                        title: "limitSwap.asset".localized,
                        isValid: bothAssetsPicked,
                        showValue: focusedSection != .asset,
                        focusedField: $focusedSection,
                        focusedFieldEquals: .asset,
                        cornerRadius: 24,
                        onExpand: { isExpanded in
                            focusedSection = isExpanded ? .asset : nil
                        },
                        content: {
                            LimitAssetSwapForm(
                                vm: vm,
                                fromCoin: fromCoin,
                                toCoin: toCoin,
                                sourceAmountText: $sourceAmountText,
                                onPickFromAsset: onPickFromAsset,
                                onPickToAsset: onPickToAsset,
                                onSwapAssets: onSwapAssets
                            )
                        },
                        valueView: {
                            LimitAssetCompactValue(
                                fromAsset: vm.draft.fromAsset,
                                toAsset: vm.draft.toAsset
                            )
                        }
                    )

                    if vm.advancedSwapQueueEnabled == false {
                        LimitUnavailableRow()
                    }

                    if let warning = vm.displayedWarning {
                        LimitWarningRow(warning: warning)
                    }
                }
            }

            PrimaryButton(
                title: "limitSwap.placeOrder".localized,
                action: onPlaceOrder
            )
            .disabled(!isPlaceable)
            .padding(.bottom, 16)
        }
        .task {
            // Drive the quote-refresh countdown ring once the view is on screen.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                await vm.tickQuoteCountdown()
            }
        }
        .onLoad {
            // Commit the initial focus so each FormExpandableSection's onChange
            // fires and animates the default section open (both start collapsed
            // on frame 0).
            if focusedSection == nil {
                focusedSection = initialFocusedSection
            }
            // Reflect an already-populated draft in the editable fields on first
            // appear — otherwise they only sync via onChange and read empty
            // until the user edits them.
            if priceText.isEmpty, vm.draft.targetPrice > 0 {
                priceText = formatPrice(vm.draft.targetPrice)
            }
            if sourceAmountText.isEmpty, vm.draft.sourceAmount > 0 {
                sourceAmountText = formatPrice(fromCoin.decimal(for: vm.draft.sourceAmount))
            }
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
            // Sync vm → text only when the local text doesn't already parse to the
            // same Decimal. Preserves a trailing "." while typing and reflects
            // preset-pill taps that mutate vm.
            if parsePrice(priceText) != newPrice {
                priceText = newPrice == 0 ? "" : formatPrice(newPrice)
            }
        }
    }

    private var isPlaceable: Bool {
        vm.draft.targetPrice > 0
            && vm.draft.sourceAmount > 0
            && vm.isAdvancedSwapQueueEnabled
    }

    /// Asset section shows the collapsed summary + checkmark/pencil once the user
    /// has a non-empty pair — true on launch since we seed from the host's coins.
    private var bothAssetsPicked: Bool {
        !vm.draft.fromAsset.ticker.isEmpty && !vm.draft.toAsset.ticker.isEmpty
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

// MARK: - Quote-refresh countdown ring
//
// Right-aligned "0:36" + progress ring in the Limit header, tied to the
// market-price refresh cadence (`LimitSwapFormViewModel.quoteRefreshCountdown`).
// The market Verify screen uses the same 60s ticker pattern.

private struct QuoteRefreshTimerRow: View {

    @Bindable var vm: LimitSwapFormViewModel

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            Text(vm.quoteRefreshCountdownLabel)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .monospacedDigit()

            ZStack {
                Circle()
                    .stroke(Theme.colors.borderLight, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(0.001, vm.quoteRefreshProgress))
                    .stroke(Theme.colors.primaryAccent3, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Execute-when content (price display + toggle + presets + expiry)

private struct LimitExecuteWhenContent: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Binding var priceText: String
    let onPickToAsset: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .trailing) {
                LimitPriceDisplay(vm: vm, priceText: $priceText, onPickToAsset: onPickToAsset)
                LimitPriceToggle(vm: vm)
                    .padding(.trailing, 4)
            }

            LimitPresetPills(vm: vm)

            LimitExpiryRow(vm: vm)
        }
    }
}

// MARK: - Centered price display
//
// Market-reference line + "1 <fromTicker>" unit chip + the editable target price
// with its USD equivalent. The editable field is ALWAYS bound to the target
// price in the target asset's terms (the memo's LIM source) — the $/asset toggle
// only swaps which representation is emphasized (large vs subtitle).
//
// NOTE (maintainer): Figma expresses the price as "1 <buyAsset> = $<usd>", which
// inverts this per-unit-rate convention. Reconciling which representation is
// canonical is a fund-safety-sensitive VM change that needs designer sign-off; it
// is intentionally NOT guessed at here (a wrong inversion would place orders at
// the reciprocal price).

private struct LimitPriceDisplay: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Binding var priceText: String
    let onPickToAsset: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            marketReference

            unitChip

            if vm.draft.displayUnit == .usd {
                Text(usdString)
                    .font(Theme.fonts.priceTitle1)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                assetPriceField(font: Theme.fonts.bodySMedium, color: Theme.colors.textTertiary)
            } else {
                assetPriceField(font: Theme.fonts.priceTitle1, color: Theme.colors.textPrimary)
                Text(usdString)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var marketReference: some View {
        if let market = vm.marketPriceRef, market > 0 {
            Text(String(format: "limitSwap.executeWhen.marketReference".localized, marketString(market)))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .lineLimit(1)
        }
    }

    private var unitChip: some View {
        Button(action: onPickToAsset) {
            HStack(spacing: 8) {
                if !vm.draft.toAsset.logo.isEmpty {
                    AsyncImageView(
                        logo: vm.draft.toAsset.logo,
                        size: CGSize(width: 24, height: 24),
                        ticker: vm.draft.toAsset.ticker,
                        tokenChainLogo: vm.draft.toAsset.chainLogo
                    )
                }
                Text(String(format: "limitSwap.executeWhen.oneUnit".localized, vm.draft.fromAsset.ticker))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 99)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func assetPriceField(font: Font, color: Color) -> some View {
        HStack(spacing: 6) {
            TextField("0", text: $priceText)
                .font(font)
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: true, vertical: false)
                .lineLimit(1)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(vm.draft.toAsset.ticker)
                .font(font)
                .foregroundStyle(color)
        }
    }

    /// USD equivalent of the target price (per the design-flags decision:
    /// `targetPrice × targetUsdPricePerUnit`). Falls back to the asset-terms
    /// value when no USD rate is available.
    private var usdString: String {
        guard vm.targetUsdPricePerUnit > 0, vm.draft.targetPrice > 0 else {
            return "$0.00"
        }
        let usd = vm.draft.targetPrice * vm.targetUsdPricePerUnit
        return "$\(formatUsd(usd))"
    }

    private func marketString(_ market: Decimal) -> String {
        if vm.targetUsdPricePerUnit > 0 {
            return "$\(formatUsd(market * vm.targetUsdPricePerUnit))"
        }
        return "\(market.formatForDisplay()) \(vm.draft.toAsset.ticker)"
    }

    private func formatUsd(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
    }
}

// MARK: - $/asset toggle (two stacked circular buttons)

private struct LimitPriceToggle: View {

    @Bindable var vm: LimitSwapFormViewModel

    var body: some View {
        VStack(spacing: 2) {
            // Top: the asset-terms view (Figma "circles" glyph — two interlocking
            // rings). Bottom: the USD toggle ($, blue-filled when active).
            toggleButton(unit: .asset, systemImage: "circlebadge.2")
            toggleButton(unit: .usd, systemImage: "dollarsign.circle")
        }
        .padding(3)
        .background(Theme.colors.bgSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func toggleButton(unit: PriceDisplayUnit, systemImage: String) -> some View {
        let isActive = vm.draft.displayUnit == unit
        return Button {
            if vm.draft.displayUnit != unit {
                vm.toggleDisplayUnit()
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? Theme.colors.textPrimary : Theme.colors.textSecondary)
                .frame(width: 32, height: 32)
                .background(isActive ? Theme.colors.primaryAccent3 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Expiry row (inside the Execute-when card)

private struct LimitExpiryRow: View {

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
        .background(Theme.colors.bgSurface1)
        .clipShape(UnevenRoundedRectangle(cornerRadii: Self.corners))
        .overlay(
            UnevenRoundedRectangle(cornerRadii: Self.corners)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
    }

    // Nests under the price area: small top corners, larger bottom corners that
    // echo the enclosing card (Figma top-12 / bottom-16).
    private static let corners = RectangleCornerRadii(
        topLeading: 12, bottomLeading: 16, bottomTrailing: 16, topTrailing: 12
    )

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

// MARK: - Collapsed Asset summary (Sell <ticker> · Buy <ticker>)
//
// Rendered by FormExpandableSection as the section's value view when the Asset
// section is collapsed. The checkmark + pencil affordances are supplied by
// FormExpandableSection itself.

private struct LimitAssetCompactValue: View {

    let fromAsset: LimitSwapAsset
    let toAsset: LimitSwapAsset

    var body: some View {
        HStack(spacing: 12) {
            chip(labelKey: "limitSwap.sell", asset: fromAsset)
            chip(labelKey: "limitSwap.buy", asset: toAsset)
        }
    }

    private func chip(labelKey: String, asset: LimitSwapAsset) -> some View {
        HStack(spacing: 4) {
            Text(labelKey.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            if !asset.logo.isEmpty {
                AsyncImageView(
                    logo: asset.logo,
                    size: CGSize(width: 16, height: 16),
                    ticker: asset.ticker,
                    tokenChainLogo: asset.chainLogo
                )
            }
            Text(asset.ticker)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
        }
    }
}

// MARK: - Asset swap form (Sell + middle swap button + Buy)
//
// Inner content of the Asset FormExpandableSection's expanded state.

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

    /// Buy amount preview — the VM derives it from the signed `computeLim`
    /// path so it can't diverge from the memo's truncated LIM. `nil` when not
    /// yet computable (row shows "0").
    private var buyAmountDecimal: Decimal? {
        let amount = vm.expectedBuyAmount
        return amount > 0 ? amount : nil
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

// MARK: - Preset pills
//
// The +1% / +5% / +10% pills are always static. The Market pill is dynamic but
// only after a *manual* edit — while any preset is the live source it stays
// static "Market". Uses `LimitPillFlow` so it wraps to a second row when the
// dynamic Market pill's content grows.

private struct LimitPresetPills: View {

    @Bindable var vm: LimitSwapFormViewModel

    var body: some View {
        // Figma lays the four presets out as equal-width pills filling the row.
        HStack(spacing: 6) {
            marketPill
            staticPill(titleKey: "limitSwap.preset.plus1", pct: 1)
            staticPill(titleKey: "limitSwap.preset.plus5", pct: 5)
            staticPill(titleKey: "limitSwap.preset.plus10", pct: 10)
        }
    }

    @ViewBuilder
    private var marketPill: some View {
        let rounded = roundedPctFromMarket
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
            .minimumScaleFactor(0.85)
            .pillShape()
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
                .pillShape()
        }
        .buttonStyle(.plain)
        .disabled(vm.marketPriceRef == nil)
    }

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

// MARK: - Preset pill shape
//
// Equal-width rounded outline used by every Execute-when preset pill so the row
// distributes them evenly (Figma lays them out flex-1).

private extension View {
    func pillShape() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 100)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
    }
}

// MARK: - Advanced Swap Queue unavailable row
//
// Shown when the `EnableAdvSwapQueue` mimir is resolved-disabled: THORChain
// isn't accepting resting `=<` limit orders right now, so placement is blocked
// (fail-closed).

private struct LimitUnavailableRow: View {

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.colors.alertWarning)

            Text("limitSwap.error.advancedSwapQueueDisabled".localized)
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
