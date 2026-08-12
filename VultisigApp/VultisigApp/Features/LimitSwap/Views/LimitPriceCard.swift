//
//  LimitPriceCard.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Limit price card (Uniswap-style, flat)
//
// Header: "When 1 [icon] <TICKER> is worth" (LimitExecuteWhenTitle) — the icon +
// ticker are tappable and open the from-asset picker; the $/asset toggle sits at
// the trailing edge of the same row. Body: the large editable price on the left,
// the target [icon] TICKER button on the right (tappable → to-asset picker), with
// the secondary representation beneath it. Then the market reference line — whose
// chip carries the live offset from market and opens the stepper sheet — then the
// preset pills, all four of which render statically.
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

struct LimitPriceCard: View {

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
                    action: onPickToAsset
                )
            }
            // The keyboard-avoidance anchor sits on this ROW rather than on the
            // card. The card can be taller than the viewport the keyboard leaves —
            // trivially so with the chart expanded, and reachable on a compact
            // device at large Dynamic Type without it — and scrolling a too-tall
            // card into view pushes its top, where this field is, off the screen:
            // the exact failure the anchor exists to prevent.
            .id(LimitScrollAnchor.price)

            // Directly under the price: the market reference and the offset from
            // it are the number the target is measured against and the measure
            // itself, so they read as one row. The offset chip is the way in to an
            // arbitrary target (+7.5%), which the preset pills' whole numbers
            // cannot express.
            LimitMarketOffsetRow(vm: vm, focusedField: focusedField)

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
