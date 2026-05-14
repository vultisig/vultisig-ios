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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var backgroundGlow: some View {
        // Soft blue radial glow behind the text block — replaces the
        // three concentric ellipses from the Figma with one gradient
        // that produces the same diffused brand color.
        EllipticalGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.02, green: 0.22, blue: 0.78), location: 0.00),
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0), location: 1.00)
            ],
            center: UnitPoint(x: 0.5, y: 0.5)
        )
        .offset(y: 30)
        .blur(radius: 35)
        .opacity(0.7)
    }

    private var decorativeCoins: some View {

        HStack {
            ZStack(alignment: .leading) {
                Image("qbtc-3d")
                    .resizable()
                    .frame(width: 40, height: 45)
                    .rotationEffect(Angle(degrees: -26.5))
                    .offset(x: 7, y: -55)
                Image("qbtc-3d")
                    .resizable()
                    .frame(width: 90, height: 100)
                    .rotationEffect(Angle(degrees: 13))
                    .offset(x: -30, y: 11)
                Image("qbtc-3d")
                    .resizable()
                    .frame(width: 50, height: 55)
                    .rotationEffect(Angle(degrees: 8.5))
                    .offset(x: 10, y: 72)
            }
            Spacer()
            ZStack(alignment: .trailing) {
                Image("qbtc-3d")
                    .resizable()
                    .frame(width: 87, height: 98)
                    .offset(x: 17, y: -50)
                Image("qbtc-3d")
                    .resizable()
                    .frame(width: 50, height: 55)
                    .rotationEffect(Angle(degrees: -6.84))
                    .offset(x: -10, y: 45)
            }
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

            PrimaryButton(title: "qbtcClaimBannerCta".localized, size: .small) {
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
