//
//  LimitExpiryCard.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Expiry card
//
// Its own flat card in the Uniswap layout (rather than a sub-box nested inside
// the price card), so the expiry choice reads as a peer of the price and the
// asset rather than a detail of the price.

struct LimitExpiryCard: View {

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
