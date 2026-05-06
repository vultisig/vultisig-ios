//
//  LimitSwapBodyView.swift
//  VultisigApp
//

import BigInt
import SwiftUI

/// Limit-swap body content — renders inside `SwapCryptoView` when the
/// SegmentedControl is set to Limit. Layout mirrors the Figma Place flow
/// (vultisig-ios#4232 screen 1/2/3): compact single-row asset summary, one
/// tall "Execute when" card containing the price display + preset pills +
/// expiry sub-block, and a Place Limit Order CTA at the bottom.
///
/// **Note: Place-button color discrepancy** (Figma `#0b4eff` vs iOS theme
/// turquoise) — tracked in design-flags.md item #1.
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

// MARK: - Asset summary row (compact single-row, matches Figma)

private struct LimitAssetSummaryRow: View {

    let fromAsset: LimitSwapAsset
    let toAsset: LimitSwapAsset
    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("limitSwap.asset".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            chip(label: "limitSwap.sell".localized, ticker: fromAsset.ticker, action: onPickFromAsset)
            chip(label: "limitSwap.buy".localized, ticker: toAsset.ticker, action: onPickToAsset)

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.colors.alertSuccess)

            Spacer(minLength: 0)

            Image(systemName: "pencil")
                .font(.system(size: 14))
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Theme.colors.bgSurface1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func chip(label: String, ticker: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Text(ticker)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Execute When content (price + presets + expiry sub-block, all inside one card)

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

// MARK: - Expiry sub-block (inside the Execute When card, darker background)

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
