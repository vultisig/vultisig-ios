//
//  LimitPriceToggle.swift
//  VultisigApp
//

import SwiftUI

// MARK: - $/asset toggle (two side-by-side circular buttons)
//
// Laid out horizontally so the price card spends its vertical budget on the price
// itself — the flat layout stacks every section, so vertical space is the scarce
// axis. The matched-geometry thumb is layout-agnostic: it interpolates the
// selected indicator's frame between the two chips, so it now slides on the X axis
// instead of Y with no change to the animation itself.

struct LimitPriceToggle: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            // Leading: the asset-terms view (Figma "circles" glyph — two
            // interlocking rings). Trailing: the USD toggle ($, blue-filled when
            // active).
            toggleButton(
                unit: .asset,
                systemImage: "circlebadge.2",
                accessibilityLabelKey: "limitSwap.price.unitAsset"
            )
            toggleButton(
                unit: .usd,
                systemImage: "dollarsign.circle",
                accessibilityLabelKey: "limitSwap.price.unitUsd"
            )
        }
        .padding(3)
        .background(Theme.colors.bgSurface1)
        // Track and thumb are one pair and move together. Neither `20` nor the
        // thumb's `18` was a chosen radius: both already exceeded half of the
        // 38pt track / 32pt thumb, so both rendered as the clamp. `pill` names
        // that and keeps them clamping in step if either size changes.
        .clipShape(Theme.radius.pill.shape)
    }

    private func toggleButton(
        unit: PriceDisplayUnit,
        systemImage: String,
        accessibilityLabelKey: String
    ) -> some View {
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
        // The label is an SF Symbol, so without this VoiceOver reads the symbol
        // name ("circlebadge.2"). Selection is conveyed by fill colour alone,
        // which VoiceOver can't see — hence the trait.
        .accessibilityLabel(accessibilityLabelKey.localized)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
