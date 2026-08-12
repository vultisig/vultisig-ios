//
//  LimitPresetPills.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Preset pills
//
// Shortcuts onto the offset chip above, not a separate mechanism: `selectPresetPct`
// and the sheet's `pctFromMarketChanged` both resolve through `computePresetPrice`,
// so a pill and a stepped offset of the same size place the same order — and the
// chip reads back the result whichever of the two set it.
//
// All four render statically. The Market pill used to swap its label for the
// live delta ("+12.5% ✕") after a manual price edit, which needed a wrapping
// layout for the widened pill and a piece of view state to decide which form to
// draw. The offset chip now shows that delta permanently, so both are gone.
//
// Tapping a pill dismisses the keyboard (by clearing focus, which keeps the
// shared keyboard accessory's state truthful).

struct LimitPresetPills: View {

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
        // Without a market reference a preset has nothing to offset from. Dimmed
        // to match `LimitMarketOffsetRow`, so the two controls in this card read
        // the same way rather than one looking tappable and doing nothing.
        .opacity(vm.marketPriceRef == nil ? 0.5 : 1)
    }
}
