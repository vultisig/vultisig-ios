//
//  LimitSwapBodyView.swift
//  VultisigApp
//

import BigInt
import SwiftUI

/// Corner radius for the limit form's standalone peer sections (price card,
/// expiry card). This is the OUTER radius of the market swap's reusable section
/// (`SwapFromToField`), so the limit form speaks the same radius language as the
/// rest of swap. `SwapFromToField`'s uneven 24/12 shape exists only because its
/// from/to fields are a stacked PAIR that must read as one unit (24 outside, 12
/// where they meet) — a standalone card has no neighbour to meet, so it takes the
/// outer 24 on all corners. The paired Sell/Buy rows below keep the uneven
/// pairing shape via `NotchedRectangle` (24 outside / 12 where they meet), so the
/// shared toggle seats in a real cutout instead of page-colored paint.
private let limitSectionCornerRadius: CGFloat = 24

/// Corner radius for the inline notice/warning rows. Deliberately NOT the section
/// radius: these rows are single-line annotations (~39pt tall), and a 24pt radius
/// exceeds half their height, degenerating the shape into a capsule and making
/// them read as pills rather than as messages.
private let limitNoticeCornerRadius: CGFloat = 12

/// The limit form's editable fields, as focus identities.
///
/// A `.keyboard` toolbar is NOT scoped to the TextField it is attached to — it is
/// merged across every view in the presented hierarchy. The flat layout renders
/// the price card and the Sell row at the same time, so per-field accessories
/// would collide and the Sell percentage buttons could surface while the *price*
/// is being edited (tapping one would then mutate the sell amount behind the
/// user's back). The parent therefore owns ONE keyboard toolbar and switches its
/// content on the focused field, which this enum names.
private enum LimitFocusField: Hashable {
    /// The asset-terms target price (canonical `draft.targetPrice`).
    case assetPrice
    /// The USD-denominated target price — only rendered in USD mode.
    case usdPrice
    /// The Sell amount — the only balance-derived field, so the only one that
    /// gets the percentage buttons.
    case sellAmount
}

/// Limit-swap body content — renders inside `SwapCryptoView` when the
/// SegmentedControl is set to Limit. **Uniswap-style flat layout**: the asset
/// swap form (Sell + swap button + Buy) on top, the price card ("When 1 <sell>
/// is worth <price> <buy>" + Market/+1%/+5%/+10% pills) below it, then the
/// expiry card, then the inline notices, with the Place-Order CTA pinned to the
/// bottom — the user picks what they're trading before stating the condition it
/// executes under. No collapse/expand — every input is visible at once, so the
/// price and the amount it applies to are never hidden behind a chevron.
///
/// All business logic lives in `LimitSwapFormViewModel`; this view is
/// declarative. The price field always edits `draft.targetPrice` in the target
/// asset's terms (the value the signed memo's LIM is derived from) — the $/asset
/// toggle only changes which representation is emphasized, never how the price is
/// stored, so the memo math is never at risk.
struct LimitSwapBodyView: View {

    @Bindable var vm: LimitSwapFormViewModel
    let fromCoin: Coin
    let toCoin: Coin

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
    /// Drives the single keyboard accessory below — see `LimitFocusField`.
    @FocusState private var focusedField: LimitFocusField?

    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void
    let onSwapAssets: () -> Void
    let onPlaceOrder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Asset selection comes first: the user picks what they're
                    // trading before stating the condition it executes under.
                    // The price card still names both assets ("When 1 BTC is
                    // worth X ETH") because that sentence IS the condition —
                    // its chips label the price's units and double as shortcuts
                    // to the same pickers.
                    LimitAssetSwapForm(
                        vm: vm,
                        fromCoin: fromCoin,
                        toCoin: toCoin,
                        sourceAmountText: $sourceAmountText,
                        focusedField: $focusedField,
                        onPickFromAsset: onPickFromAsset,
                        onPickToAsset: onPickToAsset,
                        onSwapAssets: onSwapAssets
                    )

                    LimitPriceCard(
                        vm: vm,
                        priceText: $priceText,
                        usdText: $usdText,
                        focusedField: $focusedField,
                        onPickFromAsset: onPickFromAsset,
                        onPickToAsset: onPickToAsset
                    )

                    LimitExpiryCard(vm: vm)

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
        #if os(iOS)
        // ONE keyboard accessory for the whole form. `.keyboard` toolbars are not
        // scoped to the field they're attached to, so sibling accessories on the
        // (simultaneously rendered) price card and Sell row would merge — the fix
        // is a single toolbar whose content follows `focusedField`. The decimal
        // pad has no return key, so Done is unconditional: every field can be
        // dismissed. The percentage buttons are gated on the Sell amount, the
        // only balance-derived field.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField == .sellAmount {
                    SwapPercentageButtons(
                        show100: !fromCoin.isNativeToken,
                        showAllPercentageButtons: $showAllPercentageButtons,
                        onTap: handleSellPercentage
                    )
                }
                Spacer()
                Button {
                    hideKeyboard()
                } label: {
                    Text("done".localized)
                }
            }
        }
        #endif
        .onLoad {
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

    #if os(iOS)
    /// Sets the Sell amount to `pct`% of the source balance. Assigns the field
    /// text (its `onChange` funnels the value into `draft.sourceAmount`); the
    /// balance math + formatting live in the VM (market parity). Owned by the
    /// parent because the keyboard accessory that calls it is — and iOS-only for
    /// the same reason: macOS has no keyboard accessory, so it has no caller.
    private func handleSellPercentage(_ pct: Int) {
        showAllPercentageButtons = false
        sourceAmountText = vm.sourceAmountText(forPercentage: pct, of: fromCoin)
    }
    #endif

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

// MARK: - Limit price card (Uniswap-style, flat)
//
// Header: "When 1 [icon] <TICKER> is worth" (LimitExecuteWhenTitle) — the icon +
// ticker are tappable and open the from-asset picker; the $/asset toggle sits at
// the trailing edge of the same row. Body: the large editable price on the left,
// the target [icon] TICKER button on the right (tappable → to-asset picker), with
// the secondary representation beneath it. Then the market reference line, then
// the preset pills (the Market pill is dynamic — see LimitPresetPills).
//
// The editable field is ALWAYS bound to the target price in the target asset's
// terms (the memo's LIM source) — the $/asset toggle only swaps which
// representation is emphasized (large vs subtitle).
//
// NOTE (maintainer): Figma expresses the price as "1 <buyAsset> = $<usd>", which
// inverts this per-unit-rate convention. Reconciling which representation is
// canonical is a fund-safety-sensitive VM change that needs designer sign-off; it
// is intentionally NOT guessed at here (a wrong inversion would place orders at
// the reciprocal price).

private struct LimitPriceCard: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Binding var priceText: String
    @Binding var usdText: String
    /// Owned by `LimitSwapBodyView`, which renders the single keyboard accessory.
    var focusedField: FocusState<LimitFocusField?>.Binding
    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void

    /// USD-mode editing is only offered when a USD rate for the target is known;
    /// otherwise the USD value stays a read-only reflection.
    private var usdEditable: Bool { vm.targetUsdPricePerUnit > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                LimitExecuteWhenTitle(
                    asset: vm.draft.fromAsset,
                    onTapAsset: onPickFromAsset
                )

                Spacer(minLength: 8)

                LimitPriceToggle(vm: vm)
            }

            HStack(alignment: .center) {
                // The primary/secondary representations swap on toggle; a new
                // identity per unit + an opacity transition crossfades them (the
                // toggle wraps the mutation in withAnimation). Storage of
                // draft.targetPrice is unchanged — only which representation is
                // emphasised.
                priceValues
                    .id(vm.draft.displayUnit)
                    .transition(.opacity)

                Spacer(minLength: 8)

                // The trailing chip names the unit the price is quoted in AND
                // opens the to-asset picker — the flat layout's stand-in for the
                // accordion's inline ticker label.
                LimitAssetChip(
                    asset: vm.draft.toAsset,
                    iconSize: 20,
                    font: Theme.fonts.priceBodyL,
                    action: onPickToAsset
                )
            }

            LimitPresetPills(vm: vm)
        }
        .padding(16)
        .overlay(
            RoundedRectangle(cornerRadius: limitSectionCornerRadius)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: limitSectionCornerRadius))
    }

    @ViewBuilder
    private var priceValues: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                .multilineTextAlignment(.leading)
                // `.fixedSize()` on BOTH axes so the field's frame collapses to its
                // text — otherwise macOS keeps the field at its taller intrinsic
                // height, so the caret/placeholder sit off the `$` baseline.
                .fixedSize()
                .lineLimit(1)
                .focused(focusedField, equals: .usdPrice)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }

    /// Editable asset-terms price field — the canonical `draft.targetPrice`. The
    /// unit it is quoted in is named by the adjacent `targetAssetButton`.
    private func assetPriceField(font: Font, color: Color) -> some View {
        TextField("0", text: $priceText.decimalOnly())
            // `.plain` strips macOS's default bordered chrome (the dark bezel box);
            // iOS is unaffected. Matches the market amount field.
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(.leading)
            // `.fixedSize()` on BOTH axes so the field's frame collapses to its
            // text — otherwise macOS keeps the field at its taller intrinsic
            // height, so the caret/placeholder sit off the target-asset button's
            // baseline.
            .fixedSize()
            .lineLimit(1)
            .focused(focusedField, equals: .assetPrice)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
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

    private func formatUsd(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
    }
}

// MARK: - Tappable asset chip
//
// The shared construction behind BOTH asset-picker chips in the price card (the
// "When 1 [chip] is worth" source chip and the trailing target chip), so the two
// stay symmetric with each other. Matches the established asset-pill style used by
// `LimitAssetRow` — filled `bgSurface2` capsule with the 6/12/6 padding — so the
// fill (not just a border) is what signals "tappable". Only the icon size + font
// vary, tied to the type scale of the row each chip sits in.

private struct LimitAssetChip: View {

    let asset: LimitSwapAsset
    let iconSize: CGFloat
    let font: Font
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !asset.logo.isEmpty {
                    AsyncImageView(
                        logo: asset.logo,
                        size: CGSize(width: iconSize, height: iconSize),
                        ticker: asset.ticker,
                        tokenChainLogo: asset.chainLogo
                    )
                }
                Text(asset.ticker)
                    .font(font)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(Theme.colors.bgSurface2)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Execute When card title
//
// "When 1 [icon] <TICKER> is worth" — the icon + ticker reference the source
// asset (the thing being sold) and are tappable as a single chip that opens the
// from-asset picker.

private struct LimitExecuteWhenTitle: View {

    let asset: LimitSwapAsset
    let onTapAsset: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("limitSwap.executeWhen.headerWhenOne".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            LimitAssetChip(
                asset: asset,
                iconSize: 16,
                font: Theme.fonts.bodySMedium,
                action: onTapAsset
            )

            Text("limitSwap.executeWhen.headerIsWorth".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .lineLimit(1)
    }
}

// MARK: - $/asset toggle (two side-by-side circular buttons)
//
// Laid out horizontally so the price card spends its vertical budget on the price
// itself — the flat layout stacks every section, so vertical space is the scarce
// axis. The matched-geometry thumb is layout-agnostic: it interpolates the
// selected indicator's frame between the two chips, so it now slides on the X axis
// instead of Y with no change to the animation itself.

private struct LimitPriceToggle: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            // Leading: the asset-terms view (Figma "circles" glyph — two
            // interlocking rings). Trailing: the USD toggle ($, blue-filled when
            // active).
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

// MARK: - Expiry card
//
// Its own flat card in the Uniswap layout (rather than a sub-box nested inside
// the price card), so the expiry choice reads as a peer of the price and the
// asset rather than a detail of the price.

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
            RoundedRectangle(cornerRadius: limitSectionCornerRadius)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: limitSectionCornerRadius))
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

// MARK: - Asset swap form (Sell + middle swap button + Buy)
//
// A flat card in the Uniswap layout — always visible alongside the price, so the
// amount the target price applies to is never hidden.

private struct LimitAssetSwapForm: View {

    @Bindable var vm: LimitSwapFormViewModel
    let fromCoin: Coin
    let toCoin: Coin
    @Binding var sourceAmountText: String
    /// Owned by `LimitSwapBodyView`, which renders the single keyboard accessory.
    var focusedField: FocusState<LimitFocusField?>.Binding
    let onPickFromAsset: () -> Void
    let onPickToAsset: () -> Void
    let onSwapAssets: () -> Void

    var body: some View {
        ZStack {
            // Shared with the notch-center inset so the toggle seats in a full circle.
            VStack(spacing: swapCardSpacing) {
                LimitAssetRow(
                    kind: .sell,
                    coin: fromCoin,
                    asset: vm.draft.fromAsset,
                    amountText: $sourceAmountText,
                    editableFocus: .sellAmount,
                    focusedField: focusedField,
                    computedAmount: nil,
                    usdPricePerUnit: Decimal(fromCoin.price),
                    onPickAsset: onPickFromAsset
                )

                LimitAssetRow(
                    kind: .buy,
                    coin: toCoin,
                    asset: vm.draft.toAsset,
                    amountText: .constant(formattedBuyAmount),
                    editableFocus: nil,
                    focusedField: focusedField,
                    computedAmount: buyAmountDecimal,
                    usdPricePerUnit: vm.targetUsdPricePerUnit,
                    onPickAsset: onPickToAsset
                )
            }

            // Shared with the market swap form: same visual + spring flip.
            SwapAssetsButton {
                onSwapAssets()
            }
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
}

private struct LimitAssetRow: View {

    let kind: LimitAssetRowKind
    let coin: Coin
    let asset: LimitSwapAsset
    @Binding var amountText: String
    /// Non-nil when the amount is user-editable, and names the field's focus
    /// identity — the two are inseparable, since an editable field is exactly
    /// what the parent's keyboard accessory has to distinguish. `nil` renders the
    /// amount as read-only text (the computed Buy side).
    let editableFocus: LimitFocusField?
    /// Owned by `LimitSwapBodyView`, which renders the single keyboard accessory.
    var focusedField: FocusState<LimitFocusField?>.Binding
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
                    if let editableFocus {
                        TextField("0", text: $amountText.decimalOnly())
                            // `.plain` strips macOS's default bordered chrome (the
                            // dark bezel box); iOS is unaffected. Matches the market
                            // amount field.
                            .textFieldStyle(.plain)
                            .font(Theme.fonts.title2)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .focused(focusedField, equals: editableFocus)
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
            // Sell is the base shape (bottom notch, 24 top / 12 bottom); Buy is the
            // same shape rotated 180° (notch on top, 12 top / 24 bottom). The notch
            // center is inset half the inter-row gap so both rows' notches meet as
            // one full circle around the shared toggle where the rows meet.
            NotchedRectangle(notchCenterInset: swapCardSpacing / 2)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
                .rotationEffect(.degrees(kind == .sell ? 0 : 180))
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
        // Locale-aware so the fiat sub-line doesn't mis-read a pasted grouped
        // number (shares the parser the amount field itself uses).
        return parseLimitDecimal(amountText)
    }
}

// MARK: - Preset pills
//
// Layout uses a custom `LimitPillFlow` so pills wrap to a second row when the
// dynamic Market pill's content (e.g. "+12.5% ✕") is too wide for one row. The
// +1% / +5% / +10% pills are always static and just call `selectPresetPct(pct)`.
// The Market pill is dynamic but only after a *manual* edit — when any preset is
// the live source (`vm.lastPresetPct != nil`), it stays static "Market". Tapping
// any pill dismisses the keyboard so it doesn't linger after a selection.

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
        // Render statically when *any* preset is the live source (including the
        // Market preset) OR when there's effectively no delta from market. The
        // dynamic state only kicks in after the user manually edits the price
        // (which sets `vm.lastPresetPct = nil`).
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

    /// Rounds `vm.pctFromMarket` to the nearest 0.5%. Returns 0 when no market
    /// reference is loaded yet, when target price is 0, or when the actual pct
    /// rounds to 0 (i.e. |pct| < 0.25%).
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
// Intrinsically-sized rounded outline: each pill hugs its own content so
// `LimitPillFlow` can wrap a grown Market pill to its own row instead of
// cropping it.

private extension View {
    func pillShape() -> some View {
        self
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 100)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
    }
}

// MARK: - Pill flow layout
//
// Wraps subviews to a second row when content overflows the available width.
// Each child is sized by its own intrinsic content (so the dynamic Market pill
// grows when its label becomes "+12.5% ✕"); other pills can drop to the next line
// instead of getting cropped.

private struct LimitPillFlow: Layout {

    let spacing: CGFloat

    init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = arrange(subviews: subviews, in: width)
        let totalHeight = lines.map(\.height).reduce(0, +)
            + CGFloat(max(0, lines.count - 1)) * spacing
        let widestLine = lines.map(\.width).max() ?? 0
        return CGSize(width: widestLine, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
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
            RoundedRectangle(cornerRadius: limitNoticeCornerRadius)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: limitNoticeCornerRadius))
    }
}

// MARK: - Generic blocking-notice row
//
// A message-driven sibling of `LimitUnavailableRow`, used for the pair-not-
// routable / unsupported-asset gate: the coin picker filters by CHAIN
// routability only, so a poolless pair (e.g. RUNE→VULT) slips through — the
// market-price probe's failure surfaces here and the Place CTA is disabled while
// it shows.

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
            RoundedRectangle(cornerRadius: limitNoticeCornerRadius)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: limitNoticeCornerRadius))
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
            RoundedRectangle(cornerRadius: limitNoticeCornerRadius)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: limitNoticeCornerRadius))
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
