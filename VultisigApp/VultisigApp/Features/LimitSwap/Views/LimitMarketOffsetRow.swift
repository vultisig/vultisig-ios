//
//  LimitMarketOffsetRow.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Market reference + percent offset
//
// The live market price on the left, and the target's offset from it on the
// right. The offset used to exist only as a label inside the Market preset pill,
// which meant the number was visible only after a manual price edit and could not
// be set at all. Here it is both a permanent readout and the way in to an
// arbitrary target — "5% up from here" is how traders state a limit price, and it
// is the one the preset pills' whole numbers cannot express.
//
// The chip is a BUTTON onto the stepper sheet, not a text field. Typing an offset
// meant a keyboard with a minus key over a form whose every other field takes the
// decimal pad, and a two-way text mirror of the price that had to be defended
// against its own echo on every quote, drag and preset tap. The value only ever
// moves in tenths, so a stepper states that directly and the mirror disappears.
//
// Disabled with the price until a market reference resolves. That is deliberate
// surface: before this row existed, tapping a preset pill with no reference
// silently did nothing.

struct LimitMarketOffsetRow: View {

    @Bindable var vm: LimitSwapFormViewModel
    /// Owned by `LimitSwapBodyView`, which renders the single keyboard accessory.
    var focusedField: FocusState<LimitFocusField?>.Binding

    @State private var isEditingOffset = false

    var body: some View {
        HStack(spacing: 8) {
            Text(marketReferenceText)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            offsetChip
        }
        .crossPlatformSheet(isPresented: $isEditingOffset) {
            LimitCustomOffsetSheet(vm: vm, isPresented: $isEditingOffset)
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

    private var offsetChip: some View {
        Button {
            // Native focus release rather than a `resignFirstResponder` hop, so
            // the shared keyboard accessory — whose contents switch on this value
            // — doesn't keep rendering a dismissed field's controls. It also keeps
            // the keyboard from coming up over the sheet that is about to present.
            focusedField.wrappedValue = nil
            isEditingOffset = true
        } label: {
            HStack(spacing: 4) {
                Text("limitSwap.price.vsMarket".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)

                Text(formatLimitPercent(vm.pctFromMarket))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(offsetTint)
                    .lineLimit(1)

                Text("%")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)

                // A size up from the caption text around it — at 10pt it read as
                // punctuation on a label rather than as the one thing on this row
                // you can press. Tint stays tertiary, with the taller pill and the
                // body-size value carrying the affordance instead.
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.colors.textTertiary)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.colors.bgSurface1)
            .overlay(
                Theme.radius.pill.shape
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
            .clipShape(Theme.radius.pill.shape)
            // The pill is the whole tap target, and it was ~24pt tall — under any
            // reasonable minimum and, from the outside, indistinguishable from the
            // read-only market text beside it.
            .contentShape(Theme.radius.pill.shape)
        }
        .buttonStyle(.plain)
        .disabled(vm.marketPriceRef == nil)
        .opacity(vm.marketPriceRef == nil ? 0.5 : 1)
    }

    /// A below-market target is the one case worth colouring: it means the order
    /// fills the moment it rests, which is the opposite of what most people think
    /// they are placing. The matching warning row spells it out; this is the
    /// glanceable version of the same fact.
    private var offsetTint: Color {
        // Matches what the chip PRINTS, not the raw sign: flooring the price
        // leaves Market a relative 1e-8 below market, and colouring that as a
        // below-market target would warn about an order the user asked to place
        // at market.
        let pct = vm.pctFromMarket
        return limitPercentIsEffectivelyZero(pct) || pct > 0
            ? Theme.colors.textPrimary
            : Theme.colors.alertWarning
    }

    /// The reference is formatted by the SAME function as the target price, so
    /// the two are comparable digit for digit — and so a pair whose price needs
    /// more than 8 decimal places doesn't show a market that looks identical to a
    /// target it is measurably away from, which is what made the offset chip look
    /// wrong on RUNE→BTC.
    private func formatMarketPrice(_ value: Decimal) -> String {
        formatLimitPrice(value)
    }
}
