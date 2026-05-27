//
//  ValidatorCard.swift
//  VultisigApp
//
//  Per-validator row in the cosmos validator-picker sheet. Matches Figma
//  node `75918:75443` — 36pt monogram avatar (first letter of the moniker
//  on a gradient circle, per Figma `75963:74534`), moniker, voting power as
//  the subline, commission % on the right, optional check on selection.
//

import SwiftUI

struct ValidatorCard: View {
    let validator: CosmosValidator
    let chainTicker: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(validator.moniker.isEmpty ? validator.operatorAddress.truncated() : validator.moniker)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                    Text(votingPowerText)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(commissionText)
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

    private var avatar: some View {
        KeybaseAvatarView(
            identity: validator.identity,
            monogram: monogram,
            size: 36
        )
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

    private var monogram: String {
        let source = validator.moniker.isEmpty ? validator.operatorAddress : validator.moniker
        return String(source.prefix(1)).uppercased()
    }

    private var votingPowerText: String {
        let display = formatVotingPower(validator.votingPower, decimals: 6)
        return "\(display) \(chainTicker)"
    }

    private var commissionText: String {
        let percentage = validator.commission * 100
        let nsNumber = NSDecimalNumber(decimal: percentage)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: nsNumber) ?? "0")%"
    }

    /// Voting power arrives as base-units `Decimal` (uluna). For display we
    /// scale down by the chain's native decimals and round to thousands so
    /// values like "200,392 LUNA" match the Figma reference.
    private func formatVotingPower(_ value: Decimal, decimals: Int) -> String {
        let divisor = pow(Decimal(10), decimals)
        let scaled = value / divisor
        let nsNumber = NSDecimalNumber(decimal: scaled)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: nsNumber) ?? "0"
    }
}

private extension String {
    /// Compact `terravaloper1abc…xyz` truncation for fallback display.
    func truncated() -> String {
        guard count > 14 else { return self }
        return prefix(8) + "…" + suffix(4)
    }
}
