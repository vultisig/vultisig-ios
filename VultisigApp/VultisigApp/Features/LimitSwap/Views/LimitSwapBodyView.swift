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
private let limitSectionCornerRadius = Theme.radius.xl

/// Corner radius for the inline notice/warning rows. Deliberately NOT the section
/// radius: these rows are single-line annotations (~39pt tall), and a 24pt radius
/// exceeds half their height, degenerating the shape into a capsule and making
/// them read as pills rather than as messages.
private let limitNoticeCornerRadius: CornerRadius = Theme.radius.md

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
    /// The percent-offset-from-market field. Bound two-way to the price, and the
    /// only field whose sign is meaningful, so it takes a keyboard with a minus
    /// key rather than the decimal pad the others use.
    case pctFromMarket
}

/// Limit-swap body content — renders inside `SwapCryptoView` when the
/// SegmentedControl is set to Limit. **Uniswap-style flat layout**: the asset
/// swap form (Sell + swap button + Buy) on top, the price card ("When 1 <sell>
/// is worth <price> <buy>" + Market/+1%/+5%/+10% pills) below it, then the
/// expiry card, then the inline notices, with the Place-Order CTA pinned to the
/// bottom — the user picks what they're trading before stating the condition it
/// executes under. Every input is visible at once, so the price and the amount
/// it applies to are never hidden behind a chevron.
///
/// The price chart is the one collapsible thing here, and it does not breach
/// that rule: it is an optional *way* of choosing a price the field and the
/// preset pills can already set, both of which stay on screen. It starts
/// collapsed and, while collapsed, is not fetched at all.
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
    /// Percent-offset-from-market mirror of the price. Editable; two-way bound to
    /// `draft.targetPrice` through the VM's `pctFromMarketChanged` / `pctFromMarket`.
    @State private var pctText: String = ""
    /// The last value written to `pctText` PROGRAMMATICALLY (by `syncPctText`),
    /// absorbed by `onChange(pctText)` exactly as `lastSyncedUsdText` is for the
    /// USD mirror. Without it, a resync triggered while the field is focused
    /// (a chart drag, a preset tap, a fresh quote) would echo back through the
    /// two-decimal display form and re-round the canonical price it just read.
    @State private var lastSyncedPctText: String?
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
        // Evaluated once and threaded through both consumers — the inline notice
        // and the CTA's disabled state have to agree, and re-deriving it per read
        // would run the affordability math twice on every body pass.
        let balance = vm.balanceState(sourceCoin: fromCoin)
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
                        pctText: $pctText,
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

                    // Says which asset is short — funds or gas — instead of
                    // letting the user find out one screen later at Verify.
                    // Silent while the fee estimate is in flight, so a gas error
                    // is never shown and then withdrawn.
                    if let balanceMessage = balance.noticeMessage {
                        LimitNoticeRow(message: balanceMessage)
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
            .disabled(!vm.canPlaceOrder(sourceCoin: fromCoin))
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
                    // Clearing focus rather than resigning first responder via
                    // UIApplication: this toolbar's own contents switch on
                    // `focusedField`, so dismissing by a route that leaves that
                    // value stale would leave the accessory believing a field is
                    // still being edited.
                    focusedField = nil
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
            syncPctText()
        }
        .onChange(of: pctText) { _, newText in
            // Absorb the one echo of a programmatic sync, so a resync that lands
            // while the field is focused can't round-trip the canonical price
            // through this field's 2-dp display form.
            let synced = lastSyncedPctText
            lastSyncedPctText = nil
            guard isUserFieldEdit(newText: newText, lastSyncedText: synced) else { return }
            vm.pctFromMarketChanged(parseLimitPercent(newText))
        }
        .onChange(of: vm.marketPriceRef) { _, _ in
            // The reference the offset is measured against moved (pair change, or
            // the first quote landing) — the same price is now a different offset,
            // so the readout has to be re-derived even mid-edit.
            syncPctText()
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
            guard isUserFieldEdit(newText: newText, lastSyncedText: synced) else { return }
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
            syncPctText()
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

    /// Re-derive `pctText` from the canonical target price and the live market
    /// reference — but only when the field's current text no longer describes
    /// that price.
    ///
    /// The guard is a VALUE comparison, not a focus check. Gating on focus looks
    /// equivalent and is not: it suppresses every resync while the field is being
    /// edited, so a price moved by something else in that window — a chart drag,
    /// a preset, a fresh market quote arriving — would leave the offset reading a
    /// number that is no longer true of the order.
    ///
    /// Agreement is checked in BOTH directions, and it needs both. Mapping the
    /// text forward through the VM's own price arithmetic asks the semantically
    /// primary question — *does your text describe the order we would place?* —
    /// but that mapping rounds to 8 decimals and is not injective at the bottom
    /// of the range, where wildly different offsets collapse onto one price. So
    /// the offset itself is compared too, which is the quantity the field
    /// actually shows (see `limitPercentAgrees`).
    ///
    /// Text agrees → it is this field's own value, so leave it: the caret stays
    /// put mid-edit, and a typed `7.555` survives instead of being rounded into
    /// the two-decimal display form (which would leave the field disagreeing with
    /// the price actually being placed). Text disagrees → the price moved without
    /// this field, so follow it.
    ///
    /// With no market reference the offset is undefined, so the field clears
    /// rather than showing a stale percentage against a price that no longer
    /// exists (it is also disabled in that state).
    private func syncPctText() {
        guard vm.marketPriceRef != nil, vm.draft.targetPrice > 0 else {
            guard !pctText.isEmpty else { return }
            lastSyncedPctText = ""
            pctText = ""
            return
        }
        let typed = parseLimitPercent(pctText)
        if let mapped = vm.targetPrice(forPctFromMarket: typed),
           mapped == vm.draft.targetPrice,
           limitPercentAgrees(typed: typed, canonical: vm.pctFromMarket) {
            return
        }
        let text = formatLimitPercent(vm.pctFromMarket)
        guard text != pctText else { return }
        lastSyncedPctText = text
        pctText = text
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
    @Binding var pctText: String
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
                    action: onPickToAsset
                )
            }

            // Directly under the price: the market reference and the offset from
            // it are the number the target is measured against and the measure
            // itself, so they read as one row. The offset is an editable FIELD
            // rather than a readout, which is what makes an arbitrary target
            // (+7.5%) as reachable as the preset pills' whole numbers.
            LimitMarketOffsetRow(
                vm: vm,
                pctText: $pctText,
                focusedField: focusedField
            )

            // Between the price and the presets on purpose: the chart is what
            // gives a preset its meaning, so it reads as the thing the pills act
            // on rather than as an illustration tacked on below them.
            //
            // The DISCLOSURE renders unconditionally, unlike the chart inside
            // it: whether a pair has a drawable series is only known after a
            // fetch, and the fetch only happens on expand, so gating the header
            // on `pairChart` would leave nothing to tap and the chart would be
            // unreachable for every pair.
            LimitPriceChartDisclosure(vm: vm)

            LimitPresetPills(vm: vm, focusedField: focusedField)
        }
        .padding(16)
        .overlay(
            limitSectionCornerRadius.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(limitSectionCornerRadius.shape)
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

// MARK: - Market reference + percent offset
//
// The live market price on the left, and the target's offset from it — editable —
// on the right. The offset used to exist only as a label inside the Market preset
// pill, which meant the number was visible only after a manual price edit and
// could not be typed into at all. As a field it is both a permanent readout and
// the most direct way to express a limit price ("5% up from here"), which is how
// traders state one.
//
// Disabled with the price until a market reference resolves. That is deliberate
// surface: before this row existed, tapping a preset pill with no reference
// silently did nothing.

private struct LimitMarketOffsetRow: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Binding var pctText: String
    /// Owned by `LimitSwapBodyView`, which renders the single keyboard accessory.
    var focusedField: FocusState<LimitFocusField?>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Text(marketReferenceText)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            offsetField
        }
    }

    private var marketReferenceText: String {
        guard let market = vm.marketPriceRef else {
            return "limitSwap.price.marketLoading".localized
        }
        return String(
            format: "limitSwap.price.marketReference".localized,
            formatMarketPrice(market),
            vm.draft.toAsset.ticker
        )
    }

    private var offsetField: some View {
        HStack(spacing: 3) {
            Text("limitSwap.price.vsMarket".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            // Literal placeholder, matching the price and amount fields: it is a
            // numeral, not a phrase, and every shipping locale renders it the same.
            TextField("0", text: $pctText.signedDecimalOnly())
                // `.plain` strips macOS's default bordered chrome; iOS is
                // unaffected. Matches the price and amount fields.
                .textFieldStyle(.plain)
                .font(Theme.fonts.caption12)
                .foregroundStyle(offsetTint)
                .multilineTextAlignment(.trailing)
                // Sized to the widest realistic value ("-100.00") rather than
                // `.fixedSize()`: an intrinsically-sized field would resize on
                // every keystroke, sliding the "%" sideways as digits are typed.
                .frame(width: 52)
                .lineLimit(1)
                .focused(focusedField, equals: .pctFromMarket)
                #if os(iOS)
                // No `.decimalPad` here — it has no minus key, and a negative
                // offset is a legitimate entry (take the price now, with an
                // expiry attached). `.numbersAndPunctuation` keeps the sign
                // reachable; `signedDecimalOnly` rejects everything else.
                .keyboardType(.numbersAndPunctuation)
                #endif

            Text("%")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.colors.bgSurface1)
        .overlay(
            Theme.radius.pill.shape
                .stroke(
                    focusedField.wrappedValue == .pctFromMarket
                        ? Theme.colors.primaryAccent3
                        : Theme.colors.borderLight,
                    lineWidth: 1
                )
        )
        .clipShape(Theme.radius.pill.shape)
        .disabled(vm.marketPriceRef == nil)
        .opacity(vm.marketPriceRef == nil ? 0.5 : 1)
    }

    /// A below-market target is the one case worth colouring: it means the order
    /// fills the moment it rests, which is the opposite of what most people think
    /// they are placing. The matching warning row spells it out; this is the
    /// glanceable version of the same fact.
    private var offsetTint: Color {
        vm.pctFromMarket < 0 ? Theme.colors.alertWarning : Theme.colors.textPrimary
    }

    /// Market reference formatting — 8 significant decimals like the price field,
    /// so the reference and the target are directly comparable digit for digit.
    private func formatMarketPrice(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }
}

// MARK: - Price chart disclosure
//
// The chart is opt-in and starts collapsed. It is an optional way to set a price
// the form can already set numerically — the field and the preset pills stay
// visible either way — so it earns its vertical space only from users who ask
// for it, and costs no market-data traffic from the ones who don't.
//
// This is the single exception to the flat layout's "no collapse/expand" rule
// (see this file's header): that rule exists so the price and the amount it
// applies to are never hidden behind a chevron, and neither is. What collapses
// is one *way* of choosing the price, never the price itself.

private struct LimitPriceChartDisclosure: View {

    @Bindable var vm: LimitSwapFormViewModel

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { vm.isChartExpanded },
            set: { vm.setChartExpanded($0, currency: SettingsCurrency.current) }
        )
    }

    var body: some View {
        ExpandableView(isExpanded: isExpanded) {
            header
        } content: {
            content
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("limitSwap.chart.title".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(Theme.fonts.caption10)
                .bold()
                .foregroundStyle(Theme.colors.textTertiary)
                .rotationEffect(.degrees(vm.isChartExpanded ? 180 : 0))
                .animation(.easeInOut(duration: 0.2), value: vm.isChartExpanded)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        if let chart = vm.pairChart {
            LimitPriceChartSection(vm: vm, chart: chart)
                .padding(.top, 4)
        } else if vm.isLoadingPairChart {
            // Reserves the chart's own height so expanding settles at its final
            // size once, instead of growing to a spinner and growing again to
            // the plot.
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: LimitPriceChartSection.chartHeight)
        } else {
            Text("limitSwap.chart.unavailable".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
        }
    }
}

// MARK: - Price chart section
//
// The chart, the window picker under it, and the one-line verdict on whether the
// pair has ever been where the target is. The verdict is the part that answers
// the question a limit price actually raises — "is this reachable?" — and is
// also the part that makes the expiry pills legible.

private struct LimitPriceChartSection: View {

    @Bindable var vm: LimitSwapFormViewModel
    let chart: MarketChart

    /// Ranges offered here, deliberately not `MarketChartRange.allCases`. `1D`
    /// is omitted: the drag zone spans the preset pills' reach, ~15%, and an
    /// intraday range is a fraction of that, so the history draws as a flat
    /// ribbon whatever the domain policy. Coin detail keeps 1D because there the
    /// plot is only ever a picture; here it is also an input.
    private static let ranges: [MarketChartRange] = [.week, .month, .year, .all]

    /// Shared with the disclosure's loading placeholder so expanding settles at
    /// its final height once rather than growing twice.
    static let chartHeight: CGFloat = 148

    private var market: Double? {
        vm.marketPriceRef.map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    private var target: Double {
        NSDecimalNumber(decimal: vm.draft.targetPrice).doubleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LimitPriceChartView(
                chart: chart,
                market: market,
                target: target,
                targetLabel: targetLabel,
                onTargetChanged: vm.targetPriceChangedFromChart
            )
            .frame(height: Self.chartHeight)
            .opacity(vm.isLoadingPairChart ? 0.45 : 1)
            // The outgoing series stays on screen, dimmed, while the next one
            // loads. Clearing it first collapses the card and the whole form
            // jumps — worse, on a range switch, than a briefly stale line.
            .animation(.easeInOut(duration: 0.2), value: vm.isLoadingPairChart)

            reachHint

            LimitChartRangePills(vm: vm, ranges: Self.ranges)
        }
    }

    private var targetLabel: String {
        "\(formatPrice(vm.draft.targetPrice)) \(vm.draft.toAsset.ticker)"
    }

    @ViewBuilder
    private var reachHint: some View {
        // Evaluated once and threaded through both consumers. Read as two
        // computed properties, the reach scan walked the whole series twice on
        // every body pass.
        let reach = verdict
        HStack(spacing: 6) {
            Circle()
                .fill(hintTint(for: reach))
                .frame(width: 5, height: 5)
            Text(hintText(for: reach))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var verdict: LimitChartReach.Verdict {
        // Same non-finite filter the chart layout applies to this series. On the
        // raw points a NaN or infinite sample survives into `.notReached(highest:)`
        // and reaches `Decimal(_: Double)`, which represents neither — so the
        // hint would render from a value the chart itself had already discarded.
        let sanitised = MarketChart(points: chart.points.filter(\.price.isFinite))
        return LimitChartReach.evaluate(chart: sanitised, target: target, market: market)
    }

    private func hintTint(for verdict: LimitChartReach.Verdict) -> Color {
        switch verdict {
        case .atOrBelowMarket: return Theme.colors.alertError
        case .lastTraded: return Theme.colors.alertSuccess
        case .notReached: return Theme.colors.textTertiary
        }
    }

    private func hintText(for verdict: LimitChartReach.Verdict) -> String {
        switch verdict {
        case .atOrBelowMarket:
            return "limitSwap.chart.fillsImmediately".localized
        case .lastTraded(let date):
            let elapsed = RelativeDateTimeFormatter()
            elapsed.unitsStyle = .full
            return String(
                format: "limitSwap.chart.lastTradedHere".localized,
                elapsed.localizedString(for: date, relativeTo: Date())
            )
        case .notReached(let highest):
            return String(
                format: "limitSwap.chart.notReached".localized,
                "\(formatPrice(Decimal(highest))) \(vm.draft.toAsset.ticker)"
            )
        }
    }

    private func formatPrice(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }
}

private struct LimitChartRangePills: View {

    @Bindable var vm: LimitSwapFormViewModel
    let ranges: [MarketChartRange]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ranges) { range in
                let isSelected = vm.chartRange == range
                Button {
                    vm.selectChartRange(range, currency: SettingsCurrency.current)
                } label: {
                    Text(range.title)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(isSelected ? Theme.colors.textPrimary : Theme.colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(isSelected ? Theme.colors.bgSurface2 : Color.clear)
                        .clipShape(Theme.radius.pill.shape)
                        // The pill is `maxWidth: .infinity` but an unselected one
                        // fills with `Color.clear`, so without an explicit content
                        // shape the tap area collapses to the glyphs and most of
                        // the button is dead — worse the wider the screen, and it
                        // only afflicts the UNSELECTED pills, which are precisely
                        // the ones being reached for.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Tappable asset chip
//
// The shared construction behind BOTH asset-picker chips in the price card (the
// "When 1 [chip] is worth" source chip and the trailing target chip), so the two
// stay symmetric with each other. Matches the established asset-pill style used by
// `LimitAssetRow` — filled `bgSurface2` capsule with the 6/12/6 padding — so the
// fill (not just a border) is what signals "tappable". The ticker takes the same
// `caption12` the Sell/Buy coin pills use, so every asset chip on the screen
// speaks one type size; only the icon scales with the row it sits in.

private struct LimitAssetChip: View {

    let asset: LimitSwapAsset
    let iconSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !asset.logo.isEmpty {
                    AsyncImageView(
                        logo: asset.logo,
                        size: CGSize(width: iconSize, height: iconSize),
                        ticker: asset.ticker,
                        // No chain badge on a native asset — its icon already IS
                        // the chain, so the badge repeats it. `LimitAssetRow`
                        // has always done this; the chips did not, so RUNE and
                        // ETH carried a redundant dot in the price card while
                        // the same assets were clean in the Sell/Buy rows.
                        tokenChainLogo: asset.isNativeToken ? nil : asset.chainLogo
                    )
                }
                Text(asset.ticker)
                    .font(Theme.fonts.caption12)
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
        // Track and thumb are one pair and move together. Neither `20` nor the
        // thumb's `18` was a chosen radius: both already exceeded half of the
        // 38pt track / 32pt thumb, so both rendered as the clamp. `pill` names
        // that and keeps them clamping in step if either size changes.
        .clipShape(Theme.radius.pill.shape)
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
                        Theme.radius.pill.shape
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

    /// The presets, unchanged from what shipped. `3d` is both the default and —
    /// on current mainnet mimir — the ceiling, so there is deliberately no longer
    /// preset to offer; anything shorter or in between is reached through Custom.
    private static let presetHours = [12, 24, 72]

    @State private var isEditingCustom = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Text("limitSwap.expiry".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(Self.presetHours, id: \.self) { hours in
                        presetPill(hours: hours)
                    }
                    customPill
                }
            }

            // Relative, never a wall-clock time. The TTL is counted from the block
            // the order joins the queue — after the deposit is observed and
            // confirmation-counted — so a timestamp computed at entry would be
            // wrong by however long the source chain takes, which on Bitcoin is
            // routinely tens of minutes. The Done screen shows a real countdown,
            // sourced from the queue itself.
            Text(String(
                format: "limitSwap.expiry.restsFor".localized,
                formatLimitExpiry(blocks: vm.draft.expiryBlocks)
            ))
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .multilineTextAlignment(.trailing)
        }
        .padding(14)
        .overlay(
            limitSectionCornerRadius.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(limitSectionCornerRadius.shape)
        .crossPlatformSheet(isPresented: $isEditingCustom) {
            LimitCustomExpirySheet(vm: vm, isPresented: $isEditingCustom)
        }
    }

    /// A preset is "selected" only when the draft's blocks match it exactly, so
    /// picking 90m through Custom leaves every preset unhighlighted rather than
    /// rounding onto the nearest one.
    private func presetPill(hours: Int) -> some View {
        let blocks = THORChainConstants.blocks(forHours: hours)
        return pill(
            // Same formatter the Custom pill and the Verify screen use, so one
            // duration is never spelled two ways. It reproduces the historical
            // labels exactly: 12h, 24h, 3d.
            title: formatLimitExpiry(blocks: blocks),
            isSelected: vm.draft.expiryBlocks == blocks
        ) {
            vm.selectExpiryBlocks(blocks)
        }
    }

    /// Carries its own value when it is the live choice, so the row always states
    /// the expiry that is actually set instead of a generic "Custom".
    private var customPill: some View {
        let isCustom = !Self.presetHours
            .map(THORChainConstants.blocks(forHours:))
            .contains(vm.draft.expiryBlocks)
        return pill(
            title: isCustom
                ? formatLimitExpiry(blocks: vm.draft.expiryBlocks)
                : "limitSwap.expiry.custom".localized,
            isSelected: isCustom
        ) {
            isEditingCustom = true
        }
    }

    private func pill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(isSelected ? Theme.colors.textPrimary : Theme.colors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Theme.colors.bgSurface2 : Color.clear)
                .overlay(
                    Theme.radius.pill.shape
                        .stroke(Theme.colors.border, lineWidth: 1)
                )
                .clipShape(Theme.radius.pill.shape)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Custom expiry sheet
//
// Edits a DURATION, because a duration is what the memo stores. A date/time
// picker was the original request, but the TTL is a block count started when the
// order joins the queue, so an absolute time chosen here would silently drift by
// the whole deposit-confirmation delay. Days/hours/minutes is the honest control,
// and the copy states what it is relative to.

private struct LimitCustomExpirySheet: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Binding var isPresented: Bool

    @State private var days = 0
    @State private var hours = 0
    @State private var minutes = 0

    private var selectedBlocks: Int {
        THORChainConstants.blocks(forMinutes: days * 1440 + hours * 60 + minutes)
    }

    private var isAtCeiling: Bool { selectedBlocks >= vm.maxExpiryBlocks }
    private var isBelowFloor: Bool { selectedBlocks < vm.minExpiryBlocks }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("limitSwap.expiry.customTitle".localized)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
                Text(String(
                    format: "limitSwap.expiry.maxHint".localized,
                    formatLimitExpiry(blocks: vm.maxExpiryBlocks)
                ))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            }

            HStack(spacing: 10) {
                stepper(titleKey: "limitSwap.expiry.daysUnit", value: $days, range: 0...maxDays)
                stepper(titleKey: "limitSwap.expiry.hoursUnit", value: $hours, range: 0...23)
                stepper(titleKey: "limitSwap.expiry.minutesUnit", value: $minutes, range: 0...59, step: 5)
            }

            noticeRow

            PrimaryButton(title: "limitSwap.expiry.set".localized) {
                vm.selectExpiryBlocks(selectedBlocks)
                isPresented = false
            }
            .disabled(isBelowFloor)
        }
        .padding(16)
        .onLoad {
            // Seed from the live draft so reopening the sheet shows what is set.
            let total = THORChainConstants.minutes(forBlocks: vm.draft.expiryBlocks)
            days = total / 1440
            hours = (total % 1440) / 60
            minutes = total % 60
        }
    }

    private var maxDays: Int {
        THORChainConstants.minutes(forBlocks: vm.maxExpiryBlocks) / 1440
    }

    /// Says which bound was hit and why, instead of letting the value be silently
    /// corrected. THORChain clamps an over-long TTL on-chain without an error, so
    /// an app that mirrored that behaviour would leave the user believing they had
    /// set a week.
    @ViewBuilder
    private var noticeRow: some View {
        if isAtCeiling {
            LimitInlineNotice(
                systemImage: "exclamationmark.triangle.fill",
                tint: Theme.colors.alertWarning,
                message: String(
                    format: "limitSwap.expiry.ceilingNotice".localized,
                    formatLimitExpiry(blocks: vm.maxExpiryBlocks)
                )
            )
        } else if isBelowFloor {
            LimitInlineNotice(
                systemImage: "exclamationmark.triangle.fill",
                tint: Theme.colors.alertWarning,
                message: String(
                    format: "limitSwap.expiry.floorNotice".localized,
                    formatLimitExpiry(blocks: vm.minExpiryBlocks)
                )
            )
        } else {
            LimitInlineNotice(
                systemImage: "clock",
                tint: Theme.colors.alertSuccess,
                message: String(
                    format: "limitSwap.expiry.restsFor".localized,
                    formatLimitExpiry(blocks: selectedBlocks)
                )
            )
        }
    }

    private func stepper(titleKey: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        VStack(spacing: 6) {
            Text(titleKey.localized)
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.textTertiary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                stepButton(systemImage: "minus", enabled: value.wrappedValue > range.lowerBound) {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                }
                Text("\(value.wrappedValue)")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(minWidth: 26)
                stepButton(systemImage: "plus", enabled: value.wrappedValue < range.upperBound) {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .overlay(
            Theme.radius.md.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(Theme.radius.md.shape)
    }

    private func stepButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Theme.colors.textPrimary : Theme.colors.textTertiary)
                .frame(width: 24, height: 24)
                .background(Theme.colors.bgSurface2)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Inline notice (shared shape)

private struct LimitInlineNotice: View {

    let systemImage: String
    let tint: Color
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(tint)

            Text(message)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .overlay(
            limitNoticeCornerRadius.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(limitNoticeCornerRadius.shape)
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
        // Both the chain chip and the coin pill open the same asset picker in the
        // Limit form, so `onTapChain` and `onTapCoin` share `onPickAsset`. Balance
        // is shown only on the Sell row (the Buy amount is computed). The editable
        // Sell field participates in the form's single keyboard toolbar via `focus`.
        SwapAssetCard<LimitFocusField>(
            label: kind.labelKey.localized,
            chainLogo: asset.chainLogo,
            chainName: asset.chain.name,
            onTapChain: onPickAsset,
            coinLogo: asset.logo,
            // No chain badge on a native asset (its icon already is the chain) —
            // matches the Market card, which passes a nil `coin.tokenChainLogo`.
            coinChainLogo: asset.isNativeToken ? nil : asset.chainLogo,
            ticker: asset.ticker,
            onTapCoin: onPickAsset,
            balance: kind == .sell ? "\(coin.balanceString) \(coin.ticker)" : nil,
            amount: $amountText,
            isEditable: editableFocus != nil,
            focus: focusedField,
            focusValue: editableFocus,
            fiat: fiatLine,
            isSecondRow: kind == .buy
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
// Shortcuts into the offset field above, not a separate mechanism: each pill
// calls the same `selectPresetPct` the field's arithmetic goes through, and the
// field shows the resulting offset whether it came from a pill or a keystroke.
//
// All four render statically. The Market pill used to swap its label for the
// live delta ("+12.5% ✕") after a manual price edit, which needed a wrapping
// layout for the widened pill and a piece of view state to decide which form to
// draw. The offset field now shows that delta permanently, so both are gone.
//
// Tapping a pill dismisses the keyboard (by clearing focus, which keeps the
// shared keyboard accessory's state truthful). The offset field then re-derives
// to the pill's value — not because focus changed, but because the pill moved
// the price, and any text that no longer describes it is resynced.

private struct LimitPresetPills: View {

    @Bindable var vm: LimitSwapFormViewModel
    /// Owned by `LimitSwapBodyView`, which renders the single keyboard accessory.
    var focusedField: FocusState<LimitFocusField?>.Binding

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
            // Native focus release rather than a `resignFirstResponder` hop, so
            // the shared keyboard accessory — whose contents switch on this
            // value — doesn't keep rendering a dismissed field's controls.
            focusedField.wrappedValue = nil
            vm.selectPresetPct(pct)
        } label: {
            Text(titleKey.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .overlay(
                    Theme.radius.pill.shape
                        .stroke(Theme.colors.borderLight, lineWidth: 1)
                )
                // `maxWidth: .infinity` with no fill leaves the tap area collapsed
                // to the glyphs without an explicit content shape — most of the
                // pill would be dead, and worse the wider the screen.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(vm.marketPriceRef == nil)
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
            limitNoticeCornerRadius.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(limitNoticeCornerRadius.shape)
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
            limitNoticeCornerRadius.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(limitNoticeCornerRadius.shape)
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
            limitNoticeCornerRadius.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(limitNoticeCornerRadius.shape)
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

    /// `decimalOnly`, plus a single leading `+`/`-`.
    ///
    /// Only the percent-from-market field needs this: it is the one input whose
    /// sign carries meaning, and `isDecimalInput` rejects a minus outright — so
    /// binding it through `decimalOnly` would make a below-market offset
    /// untypeable. The sign is accepted only in first position, so `"5-"` and
    /// `"1-2"` are still rejected, and a lone `"-"` is allowed through as a valid
    /// in-progress entry (`parseLimitPercent` reads it as 0).
    func signedDecimalOnly() -> Binding<String> {
        Binding<String>(
            get: { wrappedValue },
            set: { newValue in
                let magnitude = (newValue.first == "-" || newValue.first == "+")
                    ? String(newValue.dropFirst())
                    : newValue
                if magnitude.isDecimalInput() { wrappedValue = newValue }
            }
        )
    }
}
