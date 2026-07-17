//
//  TonPoolCard.swift
//  VultisigApp
//
//  Per-pool row in the TON staking-pool picker sheet. Mirrors `StakingValidatorCard`:
//  a 36pt monogram avatar, pool name (+ a verified badge), a min-stake subline,
//  and the pool's APY on the right (in place of commission), with an optional
//  check on selection.
//

import SwiftUI

struct TonPoolCard: View {
    let pool: TonStakingPool
    let ticker: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(pool.name.isEmpty ? pool.address.truncatedPoolAddress() : pool.name)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .lineLimit(1)
                        if pool.verified {
                            Icon(.shieldCheckFilled, color: Theme.colors.alertSuccess, size: 14)
                        }
                    }
                    Text(sublineText)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(apyText)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.alertSuccess)
                    .lineLimit(1)
                if isSelected {
                    Icon(.check, color: Theme.colors.alertSuccess, size: 16)
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
            identity: nil,
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
        let source = pool.name.isEmpty ? pool.address : pool.name
        return String(source.prefix(1)).uppercased()
    }

    private var sublineText: String {
        let minStake = pool.minStake.formatForDisplay()
        return String(format: "tonStakingMinStake".localized, minStake, ticker)
    }

    private var apyText: String {
        let nsNumber = NSDecimalNumber(value: pool.apy)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: nsNumber) ?? "0"
        return String(format: "tonStakingAPYValue".localized, value)
    }
}

private extension String {
    /// Compact `0:a447…a16a` truncation for fallback pool display.
    func truncatedPoolAddress() -> String {
        guard count > 14 else { return self }
        return prefix(8) + "…" + suffix(4)
    }
}
