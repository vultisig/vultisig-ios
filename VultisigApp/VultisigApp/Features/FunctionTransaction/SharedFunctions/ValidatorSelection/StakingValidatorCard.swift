//
//  StakingValidatorCard.swift
//  VultisigApp
//
//  Per-validator row in the shared validator-picker sheet. One card for both
//  Cosmos and Solana — 36pt avatar, name, scaled power/stake subline, commission
//  on the right, optional check on selection. All chain-specific formatting is
//  done upstream in `StakingValidator`, so this view is purely presentational.
//

import SwiftUI

struct StakingValidatorCard: View {
    let validator: StakingValidator
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                StakingValidatorAvatar(avatar: validator.avatar, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(validator.name)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                    Text(validator.subtitle)
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(validator.commission)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                if isSelected {
                    Icon(named: "check", color: Theme.colors.alertSuccess, size: 16)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            Theme.colors.bgSurface1
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.colors.alertSuccess.opacity(0.5), lineWidth: 1)
                )
        } else {
            Theme.colors.bgSurface1
        }
    }
}
