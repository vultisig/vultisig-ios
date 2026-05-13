//
//  ClaimQbtcPromoBanner.swift
//  VultisigApp
//
//  Rich promo card shown on the Bitcoin chain detail screen when the
//  user has BTC but hasn't migrated to QBTC yet. Layout mirrors the
//  Figma `Chain Detail Page - Default` banner (node 75201:107954):
//  a centered text block on a `bgSurface2` card, a radial blue glow,
//  scattered/rotated BTC coin decorations, and a primary "Claim Now"
//  pill. No close button — the banner self-hides once the vault has a
//  QBTC chain (host gates visibility on `!hasQbtcChain`).
//

import SwiftUI

struct ClaimQbtcPromoBanner: View {
    let onClaim: () -> Void

    var body: some View {
        ZStack {
            backgroundGlow
            decorativeCoins
            foreground
        }
        .frame(height: 156)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.colors.bgSurface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var backgroundGlow: some View {
        // Soft blue radial glow behind the text block — replaces the
        // three concentric ellipses from the Figma with one gradient
        // that produces the same diffused brand color.
        RadialGradient(
            colors: [
                Theme.colors.primaryAccent4.opacity(0.18),
                Theme.colors.bgSurface2.opacity(0)
            ],
            center: .center,
            startRadius: 8,
            endRadius: 200
        )
    }

    private var decorativeCoins: some View {
        // Each coin is exported pre-rotated from Figma so the shadow
        // direction stays consistent with the design — applying
        // `.rotationEffect` would also rotate the baked-in shadow and
        // break the 3D illusion. Sizes/offsets mirror the Figma's
        // scatter on the 343pt-wide banner.
        ZStack {
            Image("btc-coin-3d-l").resizable().scaledToFit()
                .frame(width: 80, height: 90)
                .offset(x: -135, y: -10)
            Image("btc-coin-3d-tl").resizable().scaledToFit()
                .frame(width: 38, height: 42)
                .offset(x: -160, y: -55)
            Image("btc-coin-3d-bl").resizable().scaledToFit()
                .frame(width: 44, height: 49)
                .offset(x: -150, y: 60)
            Image("btc-coin-3d-tr").resizable().scaledToFit()
                .frame(width: 86, height: 97)
                .offset(x: 130, y: -45)
            Image("btc-coin-3d-br").resizable().scaledToFit()
                .frame(width: 43, height: 48)
                .offset(x: 130, y: 55)
        }
    }

    private var foreground: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("qbtcClaimBannerSubtitle".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Text("qbtcClaimBannerTitle".localized)
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            .multilineTextAlignment(.center)

            PrimaryButton(title: "qbtcClaimBannerCta".localized, size: .mini) {
                onClaim()
            }
            .fixedSize()
        }
        .padding(24)
    }
}

#Preview {
    ClaimQbtcPromoBanner(onClaim: {})
        .padding()
        .background(Theme.colors.bgPrimary)
}
