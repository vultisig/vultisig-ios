//
//  LimitSwapBodyThreeSectionView.swift
//  VultisigApp
//

import BigInt
import SwiftUI

/// Limit-swap body content — renders inside `SwapCryptoView` when the
/// SegmentedControl is set to Limit. A **three-section accordion** (Asset /
/// Execute when / Amount, one open at a time) with the Place-Order CTA pinned to
/// the bottom.
///
/// The three sections split the order into the three decisions it actually is,
/// in the order they depend on each other:
///
/// 1. **Asset** — *what* pair. Everything downstream is denominated in it.
/// 2. **Execute when** — *at what price* (and for how long) it should fill.
/// 3. **Amount** — *how much* to sell, and the output that price+amount implies.
///
/// The Amount section is last because it is the only one whose displayed result
/// depends on both of the others: the reflected output is a function of the
/// pair, the target price, and the sell amount. Putting it after them means the
/// user never sees the reflection change for a reason that is scrolled off
/// screen.
///
/// All business logic lives in `LimitSwapFormViewModel`; this view is
/// declarative. The price field always edits `draft.targetPrice` in the target
/// asset's terms (the value the signed memo's LIM is derived from) — the $/asset
/// toggle only changes which representation is emphasized, never how the price is
/// stored, so the memo math is never at risk.
struct LimitSwapBodyThreeSectionView: View {

    enum FocusedSection: Hashable {
        case asset
        case executeWhen
        case amount
    }

    @Bindable var vm: LimitSwapFormViewModel
    /// The SOURCE coin. Only the source is needed as a `Coin`: it supplies the
    /// spendable balance, the decimals the amount field parses against, and the
    /// source USD rate. The target's rate reaches the form through the VM
    /// (`targetUsdPricePerUnit`), and everything else about the pair comes from
    /// `vm.draft`, so a `toCoin` would be unused.
    let fromCoin: Coin

    /// Which section is open on first launch. Defaults to Execute-when (the
    /// price card): the pair is pre-seeded from the host's coins and the target
    /// price is auto-seeded to Market, so the price is the one input that lands
    /// holding a *placeholder* the user very likely wants to change — that is
    /// what makes it more urgent than the (empty, but obviously-required) Amount.
    /// It is also the reason the user chose Limit over Market at all. Both
    /// neighbours are one tap away. The section is actually opened by `.onLoad`
    /// committing this into `focusedSection` (see below).
    var initialFocusedSection: FocusedSection = .executeWhen

    /// `nil` on frame 0, then seeded from `initialFocusedSection` in `.onLoad`.
    /// Starting at `nil` (rather than a fixed section) is what lets each
    /// `FormExpandableSection`'s `onChange(of: focusedField)` observe the
    /// transition and drive its open animation — the same nil→onLoad focus
    /// pattern the Send/Bond expandable forms use.
    @State private var focusedSection: FocusedSection?
    @State private var sourceAmountText: String = ""
    @State private var priceText: String = ""
    /// USD-mode mirror of `priceText`. Editable in USD mode; kept in sync with
    /// `draft.targetPrice` (× the target USD rate) so switching modes shows the
    /// right value. The canonical price stays `draft.targetPrice` (asset terms).
    @State private var usdText: String = ""
    /// The last value written to `usdText` PROGRAMMATICALLY (by `syncUsdText`).
    /// `onChange(usdText)` absorbs this one echo so a preset/rate/mode redraw of
    /// the USD field can't round-trip through the 2-dp USD display and mutate the
    /// canonical asset-terms price. `nil` once absorbed → the next change is a
    /// genuine user edit.
    @State private var lastSyncedUsdText: String?
    /// Mirrors the market swap: reset to `true` on a manual amount edit so the
    /// shared `SwapPercentageButtons` clears its selected-pill highlight.
    @State private var showAllPercentageButtons = true

    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void
    let onSwapAssets: () -> Void
    let onPlaceOrder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    assetSection
                    executeWhenSection
                    amountSection

                    if vm.advancedSwapQueueEnabled == false {
                        LimitUnavailableRow()
                    }

                    if let unroutable = vm.pairUnroutableReason {
                        LimitNoticeRow(message: unroutable.message)
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
            .disabled(!vm.canPlaceOrder)
            .padding(.bottom, 16)
        }
        .onLoad {
            // Commit the initial focus so each FormExpandableSection's onChange
            // fires and animates the default section open (all start collapsed
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
            if usdText.isEmpty, vm.draft.targetPrice > 0, vm.targetUsdPricePerUnit > 0 {
                let text = formatUsdValue(vm.draft.targetPrice * vm.targetUsdPricePerUnit)
                lastSyncedUsdText = text
                usdText = text
            }
            if sourceAmountText.isEmpty, vm.draft.sourceAmount > 0 {
                sourceAmountText = formatPrice(fromCoin.decimal(for: vm.draft.sourceAmount))
            }
        }
        .onChange(of: sourceAmountText) { _, newText in
            vm.amountChanged(parseLimitAmount(newText, decimals: vm.draft.fromAsset.decimals))
            // A manual edit clears the selected-percentage highlight (market parity).
            showAllPercentageButtons = true
        }
        .onChange(of: priceText) { _, newText in
            let parsed = parseLimitPrice(newText)
            if parsed != vm.draft.targetPrice {
                vm.targetPriceChanged(parsed)
            }
        }
        .onChange(of: usdText) { _, newText in
            // Convert USD → canonical asset-terms price only while USD is the
            // ACTIVE (editable) representation. In asset mode `usdText` is synced
            // in the background; gating on the mode stops that from feeding back.
            guard vm.draft.displayUnit == .usd else { return }
            // Absorb the one echo of a programmatic sync so a preset/rate/mode
            // redraw of the USD field can't round the canonical price through the
            // 2-dp USD display (or silently clear the active preset).
            let synced = lastSyncedUsdText
            lastSyncedUsdText = nil
            guard isUserUsdPriceEdit(newText: newText, lastSyncedText: synced) else { return }
            vm.targetPriceChangedFromUsd(parseLimitPrice(newText))
        }
        .onChange(of: vm.draft.targetPrice) { _, newPrice in
            // Sync vm → text only when the local text doesn't already parse to the
            // same Decimal. Preserves a trailing "." while typing and reflects
            // preset-pill taps that mutate vm.
            if parseLimitPrice(priceText) != newPrice {
                priceText = newPrice == 0 ? "" : formatPrice(newPrice)
            }
            syncUsdText(for: newPrice)
        }
        .onChange(of: vm.targetUsdPricePerUnit) { _, _ in
            // The target asset (and thus its USD rate) changed — re-derive the USD
            // field from the unchanged canonical price.
            syncUsdText(for: vm.draft.targetPrice)
        }
        .onChange(of: fromCoin) { _, newCoin in
            // The source coin's decimals changed. `sourceAmountText`'s onChange
            // only fires on TEXT edits, so without this the visible amount ("1")
            // would keep the OLD coin's raw `draft.sourceAmount` (e.g. 1 BTC's
            // 1e8 read as 1e-10 ETH). Reparse the visible text with the new coin's
            // decimals so text ↔ draft stays consistent.
            vm.amountChanged(parseLimitAmount(sourceAmountText, decimals: newCoin.decimals))
        }
    }

    // MARK: - Sections

    /// 1 — the pair. Collapsed summary: `Sell BTC · Buy ETH` (the pair is the
    /// whole content of this section, so the summary is lossless).
    private var assetSection: some View {
        FormExpandableSection(
            title: "limitSwap.asset".localized,
            isValid: bothAssetsPicked,
            showValue: focusedSection != .asset,
            focusedField: $focusedSection,
            focusedFieldEquals: .asset,
            cornerRadius: 24,
            plainSeparator: true,
            onExpand: { isExpanded in
                focusedSection = isExpanded ? .asset : nil
            },
            content: {
                LimitAssetPickerForm(
                    vm: vm,
                    fromCoin: fromCoin,
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
    }

    /// 2 — the trigger condition: target price + expiry. Expiry stays here (it
    /// did not move to Amount) because both inputs answer the section's literal
    /// question: a limit order executes when the price is met AND before the
    /// expiry elapses. They are one condition with two clauses; the amount is a
    /// separate concern.
    ///
    /// Collapsed summary: `$2,650.00 · 24h` — price in the unit the user is
    /// currently editing in, plus the expiry the section also owns.
    private var executeWhenSection: some View {
        FormExpandableSection(
            title: "limitSwap.executeWhen".localized,
            isValid: vm.draft.targetPrice > 0,
            showValue: focusedSection != .executeWhen && vm.draft.targetPrice > 0,
            focusedField: $focusedSection,
            focusedFieldEquals: .executeWhen,
            cornerRadius: 24,
            plainSeparator: true,
            onExpand: { isExpanded in
                focusedSection = isExpanded ? .executeWhen : nil
            },
            content: {
                LimitExecuteWhenContent(
                    vm: vm,
                    priceText: $priceText,
                    usdText: $usdText,
                    onPickFromAsset: onPickFromAsset
                )
            },
            valueView: {
                LimitExecuteWhenCompactValue(
                    targetPrice: vm.draft.targetPrice,
                    displayUnit: vm.draft.displayUnit,
                    toTicker: vm.draft.toAsset.ticker,
                    targetUsdPricePerUnit: vm.targetUsdPricePerUnit,
                    expiryHours: vm.draft.expiryHours
                )
            }
        )
    }

    /// 3 — how much, and what that buys. Collapsed summary: `0.5 BTC → 12.75 ETH`
    /// — the input and the reflected output together, because the pair of them is
    /// the section's actual result (either alone is only half an answer).
    private var amountSection: some View {
        FormExpandableSection(
            // Reuses the app-wide "amount" key rather than minting a
            // limit-specific duplicate — it is already the established term for
            // an amount field in every locale.
            title: "amount".localized,
            isValid: vm.draft.sourceAmount > 0,
            showValue: focusedSection != .amount && vm.draft.sourceAmount > 0,
            focusedField: $focusedSection,
            focusedFieldEquals: .amount,
            cornerRadius: 24,
            plainSeparator: true,
            onExpand: { isExpanded in
                focusedSection = isExpanded ? .amount : nil
            },
            content: {
                LimitAmountContent(
                    vm: vm,
                    fromCoin: fromCoin,
                    sourceAmountText: $sourceAmountText,
                    showAllPercentageButtons: $showAllPercentageButtons
                )
            },
            valueView: {
                LimitAmountCompactValue(
                    sellAmount: fromCoin.decimal(for: vm.draft.sourceAmount),
                    sellTicker: vm.draft.fromAsset.ticker,
                    buyAmount: vm.expectedBuyAmount,
                    buyTicker: vm.draft.toAsset.ticker
                )
            }
        )
    }

    /// Asset section shows the collapsed summary + checkmark/pencil once the user
    /// has a non-empty pair — true on launch since we seed from the host's coins.
    private var bothAssetsPicked: Bool {
        !vm.draft.fromAsset.ticker.isEmpty && !vm.draft.toAsset.ticker.isEmpty
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

    /// USD amount formatted for the editable USD field (no grouping separators
    /// so it round-trips through `parseLimitPrice`).
    private func formatUsdValue(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    /// Re-derive `usdText` from the canonical target price, skipping the rewrite
    /// when the current text already maps to `targetPrice` (so active USD typing
    /// isn't clobbered — the mapping is exact because both sides divide the typed
    /// USD by the same rate). Records the written value in `lastSyncedUsdText` so
    /// the resulting `onChange(usdText)` is absorbed instead of feeding back.
    private func syncUsdText(for targetPrice: Decimal) {
        let newText: String
        if vm.targetUsdPricePerUnit > 0 {
            let mappedAsset = parseLimitPrice(usdText) / vm.targetUsdPricePerUnit
            guard mappedAsset != targetPrice else { return }
            let usd = targetPrice * vm.targetUsdPricePerUnit
            newText = usd == 0 ? "" : formatUsdValue(usd)
        } else {
            guard !usdText.isEmpty else { return }
            newText = ""
        }
        lastSyncedUsdText = newText
        usdText = newText
    }
}

// MARK: - Shared display formatting

/// Fiat formatting for a read-only USD reflection (2 dp, grouped). Shared by the
/// price display and the amount rows so the form has ONE fiat rendering.
private func formatLimitUsd(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    formatter.groupingSeparator = ","
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
}

/// Display formatting for a read-only asset amount.
///
/// Capped at 8 fraction digits, which is EXACT rather than lossy for the value
/// this renders most: a THORChain LIM is 1e8 fixed-point, so
/// `vm.expectedBuyAmount` never carries more than 8 decimal places and no
/// rounding occurs. That matters — this figure is a guaranteed MINIMUM, and a
/// formatter that rounded the last place up would display a number the order
/// does not actually guarantee.
private func formatLimitAmount(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 8
    formatter.groupingSeparator = ","
    return formatter.string(from: NSDecimalNumber(decimal: value))
        ?? NSDecimalNumber(decimal: value).stringValue
}

// MARK: - Sell / Buy side

/// Which side of the pair a row represents. Shared by the Asset section's picker
/// rows and the Amount section's value rows so both stacked pairs get the same
/// grouped-card geometry.
private enum LimitSide {
    case sell
    case buy

    var labelKey: String {
        self == .sell ? "limitSwap.sell" : "limitSwap.buy"
    }

    var cornerRadii: RectangleCornerRadii {
        // The top row of a stacked pair is rounded top-heavy and the bottom row
        // bottom-heavy, so the two read as one grouped control.
        switch self {
        case .sell:
            return .init(topLeading: 24, bottomLeading: 12, bottomTrailing: 12, topTrailing: 24)
        case .buy:
            return .init(topLeading: 12, bottomLeading: 24, bottomTrailing: 24, topTrailing: 12)
        }
    }
}

/// The bordered card both row kinds sit in.
private extension View {
    func limitRowCard(side: LimitSide) -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(cornerRadii: side.cornerRadii)
                    .fill(Color.clear)
                    .overlay(
                        UnevenRoundedRectangle(cornerRadii: side.cornerRadii)
                            .stroke(Theme.colors.borderLight, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Keyboard accessory
//
// The limit form's decimal-pad fields (Sell amount, target price) have no
// return key, so they need a Done accessory to dismiss — the same mechanism the
// market swap uses (`SwapPercentageButtons` + `hideKeyboard()`). The Sell field
// passes the shared percentage buttons as leading content; the price field
// passes none (Done only).

private extension View {
    @ViewBuilder
    func limitKeyboardAccessory<Leading: View>(
        @ViewBuilder leading: @escaping () -> Leading
    ) -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                leading()
                Spacer()
                Button {
                    hideKeyboard()
                } label: {
                    Text("done".localized)
                }
            }
        }
        #else
        self
        #endif
    }
}

// MARK: - Execute-when content (price display + toggle + presets + expiry)

private struct LimitExecuteWhenContent: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Binding var priceText: String
    @Binding var usdText: String
    let onPickFromAsset: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Price + presets sit together (Figma gap-10) with the price box's
            // 12pt bottom padding; the expiry sub-box follows with the 6pt
            // content gap (→ ~18pt between the presets row and the expiry box).
            VStack(spacing: 10) {
                ZStack(alignment: .trailing) {
                    LimitPriceDisplay(vm: vm, priceText: $priceText, usdText: $usdText, onPickFromAsset: onPickFromAsset)
                    LimitPriceToggle(vm: vm)
                        .padding(.trailing, 4)
                }

                LimitPresetPills(vm: vm)
            }
            .padding(.bottom, 12)

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
    @Binding var usdText: String
    let onPickFromAsset: () -> Void

    /// USD-mode editing is only offered when a USD rate for the target is known;
    /// otherwise the USD value stays a read-only reflection.
    private var usdEditable: Bool { vm.targetUsdPricePerUnit > 0 }

    var body: some View {
        VStack(spacing: 6) {
            marketReference

            unitChip

            // The primary/secondary representations swap on toggle; a new identity
            // per unit + an opacity transition crossfades them (the toggle wraps
            // the mutation in withAnimation). Storage of draft.targetPrice is
            // unchanged — only which representation is emphasised.
            priceValues
                .id(vm.draft.displayUnit)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.vertical, 8)
        // Done-only keyboard accessory for the decimal-pad target-price field
        // (no percentages — the target price isn't balance-derived).
        .limitKeyboardAccessory { EmptyView() }
    }

    @ViewBuilder
    private var priceValues: some View {
        VStack(spacing: 6) {
            if vm.draft.displayUnit == .usd {
                // USD mode: the emphasized value is the editable USD field (when a
                // rate is known); the secondary is a read-only asset reflection.
                if usdEditable {
                    usdPriceField(font: Theme.fonts.priceTitle1, color: Theme.colors.textPrimary)
                } else {
                    Text(usdString)
                        .font(Theme.fonts.priceTitle1)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                assetReflection(font: Theme.fonts.bodySMedium, color: Theme.colors.textTertiary)
            } else {
                // Asset mode: the emphasized value is the editable asset field; the
                // secondary is the read-only USD reflection.
                assetPriceField(font: Theme.fonts.priceTitle1, color: Theme.colors.textPrimary)
                Text(usdString)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// Editable USD-denominated price field. Edits flow to the canonical
    /// asset-terms `draft.targetPrice` via the parent's `usdText` sync + the VM's
    /// `targetPriceChangedFromUsd` — the USD number is NEVER stored as the price.
    private func usdPriceField(font: Font, color: Color) -> some View {
        HStack(spacing: 2) {
            Text("$")
                .font(font)
                .foregroundStyle(color)
            TextField("0", text: $usdText.decimalOnly())
                // `.plain` strips macOS's default bordered chrome (the dark bezel
                // box); iOS is unaffected. Matches the market amount field, which
                // uses PlainTextFieldStyle via `.borderlessTextFieldStyle()`.
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                // `.fixedSize()` on BOTH axes so the field's frame collapses to its
                // text — otherwise macOS keeps the field at its taller intrinsic
                // height, so the caret/placeholder sit off the `$` baseline.
                .fixedSize()
                .lineLimit(1)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }

    /// Read-only reflection of the canonical asset-terms price, shown as the
    /// secondary value in USD mode (mirrors `priceText`, which the parent keeps in
    /// sync with `draft.targetPrice`).
    private func assetReflection(font: Font, color: Color) -> some View {
        Text("\(priceText.isEmpty ? "0" : priceText) \(vm.draft.toAsset.ticker)")
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
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
        // The "1 <sell>" chip: icon + tap target are the SELL (from) asset —
        // the price is expressed as "1 <from> is worth <price> <to>", so the
        // editable side here is the source. Tapping opens the from-asset picker.
        Button(action: onPickFromAsset) {
            HStack(spacing: 8) {
                if !vm.draft.fromAsset.logo.isEmpty {
                    AsyncImageView(
                        logo: vm.draft.fromAsset.logo,
                        size: CGSize(width: 24, height: 24),
                        ticker: vm.draft.fromAsset.ticker,
                        tokenChainLogo: vm.draft.fromAsset.chainLogo
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
            TextField("0", text: $priceText.decimalOnly())
                // `.plain` strips macOS's default bordered chrome (the dark bezel
                // box); iOS is unaffected. Matches the market amount field.
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                // `.fixedSize()` on BOTH axes so the field's frame collapses to its
                // text — otherwise macOS keeps the field at its taller intrinsic
                // height, so the caret/placeholder sit off the ticker's baseline.
                .fixedSize()
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
        return "$\(formatLimitUsd(usd))"
    }

    private func marketString(_ market: Decimal) -> String {
        if vm.targetUsdPricePerUnit > 0 {
            return "$\(formatLimitUsd(market * vm.targetUsdPricePerUnit))"
        }
        return "\(market.formatForDisplay()) \(vm.draft.toAsset.ticker)"
    }
}

// MARK: - $/asset toggle (two stacked circular buttons)

private struct LimitPriceToggle: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Namespace private var thumb

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
            guard vm.draft.displayUnit != unit else { return }
            // Animate the crossfade (price block) + the thumb slide together.
            // Storage of draft.targetPrice is untouched — behaviour identical.
            withAnimation(.easeInOut(duration: 0.2)) {
                vm.toggleDisplayUnit()
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? Theme.colors.textPrimary : Theme.colors.textSecondary)
                .frame(width: 32, height: 32)
                .background {
                    // The selected indicator is a single matched-geometry thumb, so
                    // it slides between the two chips instead of hard-switching.
                    if isActive {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Theme.colors.primaryAccent3)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
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
        // Figma "backgrounds/disabled" (#0b1a3a80) — the design-system token
        // with that exact base hex is bgButtonDisabled (#0b1a3a), at 50%.
        .background(Theme.colors.bgButtonDisabled.opacity(0.5))
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

// MARK: - Collapsed section summaries
//
// Rendered by FormExpandableSection as a section's value view while it is
// collapsed. The checkmark / pencil affordances are supplied by
// FormExpandableSection itself.

/// Asset — `Sell <ticker> · Buy <ticker>`.
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

/// Execute-when — `<price> · <expiry>`.
///
/// The price renders in whichever unit the user is currently editing in, so the
/// collapsed value matches what they just typed. The pair context ("1 BTC =") is
/// deliberately dropped: the Asset summary one row above already names the pair,
/// and the section title frames this as the trigger — so omitting it keeps the
/// value on one caption line instead of truncating.
private struct LimitExecuteWhenCompactValue: View {

    let targetPrice: Decimal
    let displayUnit: PriceDisplayUnit
    let toTicker: String
    let targetUsdPricePerUnit: Decimal
    let expiryHours: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(priceString)
                .font(Theme.fonts.priceCaption)
                .foregroundStyle(Theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let expiryKey {
                Text(verbatim: "·")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)

                Text(expiryKey.localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
    }

    private var priceString: String {
        if displayUnit == .usd, targetUsdPricePerUnit > 0 {
            return "$\(formatLimitUsd(targetPrice * targetUsdPricePerUnit))"
        }
        return "\(formatLimitAmount(targetPrice)) \(toTicker)"
    }

    /// The expiry pills are the only writer of `expiryHours`, so these three
    /// cases are exhaustive in practice; an unrecognized value drops the chip
    /// rather than mislabel the order's lifetime.
    private var expiryKey: String? {
        switch expiryHours {
        case 12: return "limitSwap.expiry.12h"
        case 24: return "limitSwap.expiry.24h"
        case 72: return "limitSwap.expiry.3d"
        default: return nil
        }
    }
}

/// Amount — `<sell> <ticker> → <min buy> <ticker>`.
private struct LimitAmountCompactValue: View {

    let sellAmount: Decimal
    let sellTicker: String
    let buyAmount: Decimal
    let buyTicker: String

    var body: some View {
        HStack(spacing: 6) {
            Text("\(formatLimitAmount(sellAmount)) \(sellTicker)")
                .font(Theme.fonts.priceCaption)
                .foregroundStyle(Theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.colors.textTertiary)

            Text("\(formatLimitAmount(buyAmount)) \(buyTicker)")
                .font(Theme.fonts.priceCaption)
                .foregroundStyle(Theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Asset section content (Sell picker + swap button + Buy picker)
//
// Picker-only: this section's single job is choosing the pair, so the rows carry
// no amounts. The WHOLE row is the tap target — the old layout had a chain chip
// and a coin pill side by side that both opened the same picker, so collapsing
// them into one control removes a redundant affordance rather than adding one.

private struct LimitAssetPickerForm: View {

    @Bindable var vm: LimitSwapFormViewModel
    let fromCoin: Coin
    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void
    let onSwapAssets: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                LimitAssetPickerRow(
                    side: .sell,
                    asset: vm.draft.fromAsset,
                    balanceText: "\(fromCoin.balanceString) \(fromCoin.ticker)",
                    onPickAsset: onPickFromAsset
                )

                LimitAssetPickerRow(
                    side: .buy,
                    asset: vm.draft.toAsset,
                    balanceText: nil,
                    onPickAsset: onPickToAsset
                )
            }

            // Shared with the market swap form: same visual + spring flip. Drawn
            // last so it wins hit-testing over the full-row picker buttons.
            SwapAssetsButton {
                onSwapAssets()
            }
        }
    }
}

private struct LimitAssetPickerRow: View {

    let side: LimitSide
    let asset: LimitSwapAsset
    /// Sell side only — the balance is decision-relevant when choosing what to
    /// sell. `nil` on the buy side (holding the target asset is irrelevant).
    let balanceText: String?
    let onPickAsset: () -> Void

    var body: some View {
        Button(action: onPickAsset) {
            HStack(spacing: 12) {
                if !asset.logo.isEmpty {
                    AsyncImageView(
                        logo: asset.logo,
                        size: CGSize(width: 36, height: 36),
                        ticker: asset.ticker,
                        tokenChainLogo: asset.chainLogo
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.ticker)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)

                    Text(asset.chain.name)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(side.labelKey.localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)

                    if let balanceText {
                        Text(balanceText)
                            .font(Theme.fonts.priceCaption)
                            .foregroundStyle(Theme.colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .limitRowCard(side: side)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Amount section content (Sell amount + reflected minimum output)

private struct LimitAmountContent: View {

    @Bindable var vm: LimitSwapFormViewModel
    let fromCoin: Coin
    @Binding var sourceAmountText: String
    @Binding var showAllPercentageButtons: Bool

    var body: some View {
        VStack(spacing: 8) {
            LimitAmountRow(
                side: .sell,
                labelKey: "limitSwap.sell",
                asset: vm.draft.fromAsset,
                amountText: $sourceAmountText,
                amountIsEditable: true,
                computedAmount: nil,
                usdPricePerUnit: Decimal(fromCoin.price),
                balanceText: "\(fromCoin.balanceString) \(fromCoin.ticker)"
            )
            // Reuse the market swap's percentage buttons + Done accessory on
            // the Sell amount keyboard. Attached to the row (an ancestor of
            // the field) so it scopes to the sell amount's editing session.
            .limitKeyboardAccessory {
                SwapPercentageButtons(
                    show100: !fromCoin.isNativeToken,
                    showAllPercentageButtons: $showAllPercentageButtons,
                    onTap: handleSellPercentage
                )
            }

            LimitAmountRow(
                side: .buy,
                labelKey: "limitSwap.youReceiveAtLeast",
                asset: vm.draft.toAsset,
                amountText: .constant(formattedBuyAmount),
                amountIsEditable: false,
                computedAmount: buyAmountDecimal,
                usdPricePerUnit: vm.targetUsdPricePerUnit,
                balanceText: nil
            )
        }
    }

    /// Sets the Sell amount to `pct`% of the source balance. Assigns the field
    /// text (its `onChange` funnels the value into `draft.sourceAmount`); the
    /// balance math + formatting live in the VM (market parity).
    private func handleSellPercentage(_ pct: Int) {
        showAllPercentageButtons = false
        sourceAmountText = vm.sourceAmountText(forPercentage: pct, of: fromCoin)
    }

    /// The reflected output — the VM derives it from the signed `computeLim`
    /// path, so it is the exact minimum the order guarantees and can never read
    /// higher than what the memo encodes. `nil` when not yet computable (row
    /// shows "0"). No math happens in this view.
    private var buyAmountDecimal: Decimal? {
        let amount = vm.expectedBuyAmount
        return amount > 0 ? amount : nil
    }

    private var formattedBuyAmount: String {
        guard let amount = buyAmountDecimal else { return "0" }
        return formatLimitAmount(amount)
    }
}

/// One amount row: an identity chip on the left, the number + its fiat value on
/// the right. Used for both the editable Sell amount and the read-only reflected
/// output, which are deliberately given the SAME visual weight — "you sell this,
/// you get at least that" is the section's whole message, and demoting the
/// reflection would bury the half of it the user can't control.
private struct LimitAmountRow: View {

    let side: LimitSide
    let labelKey: String
    let asset: LimitSwapAsset
    @Binding var amountText: String
    let amountIsEditable: Bool
    /// Pre-derived amount for a read-only row, used for the fiat sub-line so it
    /// doesn't re-parse the formatted (grouped) display text. `nil` on an
    /// editable row, whose fiat line parses the field itself.
    let computedAmount: Decimal?
    let usdPricePerUnit: Decimal
    let balanceText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(labelKey.localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let balanceText {
                    Text(balanceText)
                        .font(Theme.fonts.priceCaption)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                assetChip

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    amountValue

                    Text(fiatLine)
                        .font(Theme.fonts.priceCaption)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .limitRowCard(side: side)
    }

    /// Non-interactive: picking the pair is the Asset section's job. Here the
    /// coin is a label that tells you what the number is denominated in, not a
    /// control.
    private var assetChip: some View {
        HStack(spacing: 8) {
            if !asset.logo.isEmpty {
                AsyncImageView(
                    logo: asset.logo,
                    size: CGSize(width: 28, height: 28),
                    ticker: asset.ticker,
                    tokenChainLogo: asset.chainLogo
                )
            }
            Text(asset.ticker)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Theme.colors.bgSurface2)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var amountValue: some View {
        if amountIsEditable {
            TextField("0", text: $amountText.decimalOnly())
                // `.plain` strips macOS's default bordered chrome (the dark bezel
                // box); iOS is unaffected. Matches the market amount field.
                .textFieldStyle(.plain)
                .font(Theme.fonts.priceTitle1)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        } else {
            Text(amountText)
                .font(Theme.fonts.priceTitle1)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private var fiatLine: String {
        let amount = effectiveAmount
        guard usdPricePerUnit > 0, amount > 0 else { return "$0.00" }
        return "$\(formatLimitUsd(amount * usdPricePerUnit))"
    }

    private var effectiveAmount: Decimal {
        if let computedAmount {
            return computedAmount
        }
        // Locale-aware so the fiat sub-line doesn't mis-read a pasted grouped
        // number (shares the parser the amount field itself uses).
        return parseLimitDecimal(amountText)
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

// MARK: - Generic blocking-notice row
//
// A message-driven sibling of `LimitUnavailableRow`, used for the pair-not-
// routable / unsupported-asset gate: the coin picker filters by CHAIN
// routability only, so a poolless pair (e.g. RUNE→VULT) slips through — the
// market-price probe's failure surfaces here (previously `marketPriceError` was
// never rendered) and the Place CTA is disabled while it shows.

private struct LimitNoticeRow: View {

    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.colors.alertWarning)

            Text(message)
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

private extension Binding where Value == String {
    /// Wrap a text binding so an edit is accepted only when it is a valid numeric
    /// input (`isDecimalInput`). The price/amount fields then reject any letter or
    /// symbol — whether typed or pasted — instead of silently keeping its digits,
    /// which matches what the iOS `.decimalPad` enforces for free (macOS has no
    /// such keypad). A rejected edit leaves the prior value untouched.
    func decimalOnly() -> Binding<String> {
        Binding<String>(
            get: { wrappedValue },
            set: { newValue in
                if newValue.isDecimalInput() { wrappedValue = newValue }
            }
        )
    }
}
