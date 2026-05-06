//
//  LimitSwapBodyView.swift
//  VultisigApp
//

import BigInt
import SwiftUI

/// Limit-swap body content — renders inside `SwapCryptoView` when the
/// SegmentedControl is set to Limit. Bound to LimitSwapFormViewModel from §5.
///
/// Section components reuse the Defi/Bond conventions
/// (`FormExpandableSection`) per the user's feedback (2026-05-06).
///
/// **Note: Place-button color discrepancy.** The Figma uses a blue
/// `#0b4eff` for the Place Limit Order CTA; no iOS theme token matches it
/// exactly. Used the standard turquoise `PrimaryButton` here for app-wide
/// consistency; reconcile with design before ship.
/// (Tracked in design-flags.md item #1.)
struct LimitSwapBodyView: View {

    private enum FocusedSection: Hashable {
        case executeWhen
    }

    @Bindable var vm: LimitSwapFormViewModel
    @State private var focusedSection: FocusedSection? = .executeWhen

    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void
    let onPlaceOrder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    LimitAssetSummaryRow(
                        fromAsset: vm.draft.fromAsset,
                        toAsset: vm.draft.toAsset,
                        onPickFromAsset: onPickFromAsset,
                        onPickToAsset: onPickToAsset
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

                    LimitExpiryRow(vm: vm)

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
    }

    private var isPlaceable: Bool {
        vm.draft.targetPrice > 0 && vm.draft.sourceAmount > 0
    }

    private var targetPriceSummary: String {
        guard vm.draft.targetPrice > 0 else { return "" }
        let value = NSDecimalNumber(decimal: vm.draft.targetPrice).stringValue
        return "\(value) \(vm.draft.toAsset.ticker) / \(vm.draft.fromAsset.ticker)"
    }
}

// MARK: - Asset summary row

private struct LimitAssetSummaryRow: View {

    let fromAsset: LimitSwapAsset
    let toAsset: LimitSwapAsset
    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("limitSwap.asset".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            HStack(spacing: 12) {
                assetButton(label: "limitSwap.sell".localized, ticker: fromAsset.ticker, action: onPickFromAsset)
                assetButton(label: "limitSwap.buy".localized, ticker: toAsset.ticker, action: onPickToAsset)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.colors.bgSurface1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func assetButton(label: String, ticker: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Text(ticker)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.colors.bgSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Execute When content (lives inside the FormExpandableSection)

private struct LimitExecuteWhenContent: View {

    @Bindable var vm: LimitSwapFormViewModel

    var body: some View {
        VStack(spacing: 12) {
            LimitPriceDisplay(vm: vm)
            LimitPresetPills(vm: vm)
        }
    }
}

// MARK: - Price display (large price + $/asset toggle)

private struct LimitPriceDisplay: View {

    @Bindable var vm: LimitSwapFormViewModel

    var body: some View {
        ZStack {
            VStack(spacing: 5) {
                HStack(spacing: 8) {
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
        // TODO(§8): hook into a USD-per-target-asset price feed for proper
        // $/asset toggle. v1 shows the underlying targetPrice in target-asset
        // units regardless of toggle. (design-flags.md item #3.)
        let value = NSDecimalNumber(decimal: vm.draft.targetPrice).stringValue
        switch vm.draft.displayUnit {
        case .usd:
            return "$\(value)"
        case .asset:
            return "\(value) \(vm.draft.toAsset.ticker)"
        }
    }

    private var formattedSubtitle: String {
        let value = NSDecimalNumber(decimal: vm.draft.targetPrice).stringValue
        return "\(value) \(vm.draft.toAsset.ticker) / \(vm.draft.fromAsset.ticker)"
    }
}

// MARK: - Preset pills (Market / +1 / +5 / +10%)

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

// MARK: - Expiry row (12h / 24h / 3d)

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
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
