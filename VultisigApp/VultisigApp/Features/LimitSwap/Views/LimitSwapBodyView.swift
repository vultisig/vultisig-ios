//
//  LimitSwapBodyView.swift
//  VultisigApp
//

import BigInt
import SwiftUI

/// Limit-swap body content — renders inside `SwapCryptoView` when the
/// SegmentedControl is set to Limit. Layout mirrors the Figma Place flow
/// (vultisig-ios#4232 screen 1 = full asset swap-form, screens 2/3 = same
/// asset section above an expanded "Execute when" card with the price
/// display + preset pills + expiry sub-block).
struct LimitSwapBodyView: View {

    private enum FocusedSection: Hashable {
        case executeWhen
    }

    @Bindable var vm: LimitSwapFormViewModel
    let fromCoin: Coin
    let toCoin: Coin

    @State private var focusedSection: FocusedSection? = nil
    @State private var sourceAmountText: String = ""

    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void
    let onSwapAssets: () -> Void
    let onPlaceOrder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    LimitAssetSwapForm(
                        vm: vm,
                        fromCoin: fromCoin,
                        toCoin: toCoin,
                        sourceAmountText: $sourceAmountText,
                        onPickFromAsset: onPickFromAsset,
                        onPickToAsset: onPickToAsset,
                        onSwapAssets: onSwapAssets
                    )

                    FormExpandableSection(
                        title: "limitSwap.executeWhen".localized,
                        isValid: vm.draft.targetPrice > 0,
                        value: targetPriceSummary,
                        showValue: focusedSection != .executeWhen && vm.draft.targetPrice > 0,
                        focusedField: $focusedSection,
                        focusedFieldEquals: .executeWhen,
                        onExpand: { isExpanded in
                            focusedSection = isExpanded ? .executeWhen : nil
                        }
                    ) {
                        LimitExecuteWhenContent(vm: vm)
                    }

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
    }

    private var isPlaceable: Bool {
        vm.draft.targetPrice > 0 && vm.draft.sourceAmount > 0
    }

    private var targetPriceSummary: String {
        guard vm.draft.targetPrice > 0 else { return "" }
        let value = NSDecimalNumber(decimal: vm.draft.targetPrice).stringValue
        return "\(value) \(vm.draft.toAsset.ticker) / \(vm.draft.fromAsset.ticker)"
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
}

// MARK: - Asset swap form (Sell + middle swap button + Buy)

private struct LimitAssetSwapForm: View {

    @Bindable var vm: LimitSwapFormViewModel
    let fromCoin: Coin
    let toCoin: Coin
    @Binding var sourceAmountText: String
    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void
    let onSwapAssets: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("limitSwap.asset".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Rectangle()
                .fill(Theme.colors.borderLight)
                .frame(height: 1)

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
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgPrimary)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

// MARK: - Execute When content (price + presets + expiry sub-block)

private struct LimitExecuteWhenContent: View {

    @Bindable var vm: LimitSwapFormViewModel

    var body: some View {
        VStack(spacing: 12) {
            LimitPriceDisplay(vm: vm)
            LimitPresetPills(vm: vm)
            LimitExpirySubBlock(vm: vm)
        }
    }
}

// MARK: - Price display

private struct LimitPriceDisplay: View {

    @Bindable var vm: LimitSwapFormViewModel

    var body: some View {
        ZStack {
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    if !vm.draft.fromAsset.logo.isEmpty {
                        AsyncImageView(
                            logo: vm.draft.fromAsset.logo,
                            size: CGSize(width: 24, height: 24),
                            ticker: vm.draft.fromAsset.ticker,
                            tokenChainLogo: vm.draft.fromAsset.chainLogo
                        )
                    }
                    Text("1 \(vm.draft.fromAsset.ticker)")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textSecondary)
                }
                .padding(.leading, 6)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
                .background(Theme.colors.bgSurface2)
                .clipShape(Capsule())

                Text(formattedPrimaryPrice)
                    .font(Theme.fonts.priceLargeTitle)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(formattedSubtitle)
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                displayUnitToggle
            }
        }
        .frame(minHeight: 160)
    }

    private var displayUnitToggle: some View {
        VStack(spacing: 2) {
            toggleButton(unit: .asset, systemImage: "arrow.up.arrow.down")
            toggleButton(unit: .usd, systemImage: "dollarsign")
        }
        .padding(3)
        .background(Theme.colors.bgSurface12)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func toggleButton(unit: PriceDisplayUnit, systemImage: String) -> some View {
        let isActive = vm.draft.displayUnit == unit
        return Button {
            if !isActive { vm.toggleDisplayUnit() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(width: 32, height: 32)
                .background(isActive ? Theme.colors.primaryAccent3 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var formattedPrimaryPrice: String {
        let assetValue = NSDecimalNumber(decimal: vm.draft.targetPrice).stringValue
        switch vm.draft.displayUnit {
        case .usd:
            if vm.targetUsdPricePerUnit > 0 {
                let usd = vm.draft.targetPrice * vm.targetUsdPricePerUnit
                return "$\(formatUsd(usd))"
            }
            return "$\(assetValue)"
        case .asset:
            return "\(assetValue) \(vm.draft.toAsset.ticker)"
        }
    }

    private var formattedSubtitle: String {
        let assetLine = "\(NSDecimalNumber(decimal: vm.draft.targetPrice).stringValue) \(vm.draft.toAsset.ticker) / \(vm.draft.fromAsset.ticker)"
        switch vm.draft.displayUnit {
        case .usd:
            return assetLine
        case .asset:
            if vm.targetUsdPricePerUnit > 0 {
                let usd = vm.draft.targetPrice * vm.targetUsdPricePerUnit
                return "$\(formatUsd(usd))"
            }
            return assetLine
        }
    }

    private func formatUsd(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }
}

// MARK: - Preset pills

private struct LimitPresetPills: View {

    @Bindable var vm: LimitSwapFormViewModel

    var body: some View {
        HStack(spacing: 6) {
            pill(titleKey: "limitSwap.preset.market", pct: 0)
            pill(titleKey: "limitSwap.preset.plus1", pct: 1)
            pill(titleKey: "limitSwap.preset.plus5", pct: 5)
            pill(titleKey: "limitSwap.preset.plus10", pct: 10)
        }
    }

    private func pill(titleKey: String, pct: Int) -> some View {
        Button {
            vm.selectPresetPct(pct)
        } label: {
            Text(titleKey.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 100)
                        .stroke(Theme.colors.borderLight, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(vm.marketPriceRef == nil)
    }
}

// MARK: - Expiry sub-block

private struct LimitExpirySubBlock: View {

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
        .background(Theme.colors.bgButtonDisabled.opacity(0.5))
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
