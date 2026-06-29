//
//  SolanaValidatorCard.swift
//  VultisigApp
//
//  Per-validator row in the Solana validator-picker sheet. Mirrors the Cosmos
//  `ValidatorCard` layout — avatar, name, activated stake as the subline,
//  commission % on the right, optional check on selection — adapted for Solana
//  vote-account rows. The avatar shows the metadata logo when present, else a
//  deterministic monogram (same gradient circle as `KeybaseAvatarView`).
//

import SwiftUI

struct SolanaValidatorCard: View {
    let validator: SolanaValidator
    let chainTicker: String
    let chainDecimals: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(validator.displayName)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                    Text(activatedStakeText)
                        .font(Theme.fonts.priceBodyS)
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

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            monogramAvatar
            if let url = validator.logoURL {
                CachedAsyncImage(url: url, urlCache: .imageCache) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: 36, height: 36)
    }

    private var monogramAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.colors.primaryAccent3, Theme.colors.primaryAccent4],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(monogram)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
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
        String(validator.displayName.prefix(1)).uppercased()
    }

    private var activatedStakeText: String {
        let display = formatStake(validator.activatedStake, decimals: chainDecimals)
        return "\(display) \(chainTicker)"
    }

    private var commissionText: String {
        "\(validator.commission)%"
    }

    /// Activated stake arrives in lamports; scale down by the chain's native
    /// decimals and round to whole tokens for the subline.
    private func formatStake(_ value: UInt64, decimals: Int) -> String {
        let divisor = pow(Decimal(10), decimals)
        let scaled = Decimal(value) / divisor
        let nsNumber = NSDecimalNumber(decimal: scaled)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: nsNumber) ?? "0"
    }
}
