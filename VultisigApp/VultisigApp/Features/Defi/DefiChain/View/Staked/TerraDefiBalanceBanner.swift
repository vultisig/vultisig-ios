//
//  TerraDefiBalanceBanner.swift
//  VultisigApp
//
//  Hero banner above the Terra / Terra Classic DeFi tab. Renders the chain
//  name, total staked fiat value, the LUNA logo, and the decorative
//  concentric rings that make up Vultisig's signature DeFi banner look —
//  same shape as `TronDashboardView.topBanner`.
//

import SwiftUI

struct TerraDefiBalanceBanner: View {
    let chainTitle: String
    let totalFiat: String
    let logo: String
    let isLoading: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            cardBackground

            GeometryReader { geometry in
                ZStack {
                    Circle()
                        .stroke(Theme.colors.alertSuccess.opacity(0.25), lineWidth: 2)
                        .frame(width: 160, height: 160)

                    Circle()
                        .stroke(Theme.colors.alertSuccess.opacity(0.4), lineWidth: 4)
                        .frame(width: 120, height: 120)
                }
                .position(x: geometry.size.width - 50, y: geometry.size.height * 0.75)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(chainTitle)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)

                    if isLoading {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.colors.bgSurface1)
                            .frame(width: 140, height: 28)
                    } else {
                        HiddenBalanceText(totalFiat)
                            .font(Theme.fonts.priceTitle1)
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
                Spacer()

                Image(logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)
                    .clipShape(Circle())
                    .offset(x: 12, y: 20)
            }
            .padding(16)
        }
        .frame(height: 118)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Theme.colors.alertSuccess.opacity(0.09), location: 0.00),
                        Gradient.Stop(color: Theme.colors.alertSuccess.opacity(0), location: 1.00)
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.colors.primaryAccent3.opacity(0.17), lineWidth: 1)
            )
    }
}

#Preview {
    TerraDefiBalanceBanner(
        chainTitle: "Terra",
        totalFiat: "$1,240.50",
        logo: "luna",
        isLoading: false
    )
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
