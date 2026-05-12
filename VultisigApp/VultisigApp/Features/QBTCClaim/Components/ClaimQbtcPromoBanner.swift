//
//  ClaimQbtcPromoBanner.swift
//  VultisigApp
//
//  Compact promo banner shown on the Bitcoin chain detail screen when
//  the user has BTC but hasn't migrated to QBTC yet. Tapping the
//  banner takes them through the QBTC claim flow (or the Quantum
//  Security intro first when the vault has no MLDSA key). Dismissable
//  per-vault via `@AppStorage` — the host screen owns the visibility
//  flag so it can hide the banner immediately on close.
//

import SwiftUI

struct ClaimQbtcPromoBanner: View {
    let onTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image("qbtc")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("qbtcClaimBannerTitle".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text("qbtcClaimBannerSubtitle".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.colors.bgSurface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.colors.textTertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
    }
}

#Preview {
    ClaimQbtcPromoBanner(onTap: {}, onClose: {})
        .padding()
        .background(Theme.colors.bgPrimary)
}
