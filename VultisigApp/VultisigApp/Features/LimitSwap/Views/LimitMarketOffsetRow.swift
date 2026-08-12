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
            HStack(spacing: 3) {
                Text("limitSwap.price.vsMarket".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)

                Text(formatLimitPercent(vm.pctFromMarket))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(offsetTint)
                    .lineLimit(1)

                Text("%")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.colors.bgSurface1)
            .overlay(
                Theme.radius.pill.shape
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
            .clipShape(Theme.radius.pill.shape)
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
