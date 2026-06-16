//
//  YieldTopBanner.swift
//  VultisigApp
//

import SwiftUI

/// Shared "DeFi Banners" header card for the yield screens (Figma 343×158, the
/// 118-tall gradient card + the underlined "Deposited" tab below it). Provider
/// name + current USD value on the left, the provider logo (concentric-ring
/// form) overlaid on the right. Both Noon and Circle render this; the name,
/// logo, and tab title come from the provider's `YieldPresentation`.
struct YieldTopBanner: View {
    let providerName: String
    let usdValue: String
    let logoAsset: String
    let tabTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            card
            tab
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(providerName)
                .font(Theme.fonts.bodyLMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            HiddenBalanceText(usdValue)
                .font(Theme.fonts.priceTitle1)
                .foregroundStyle(Theme.colors.textPrimary)
                .contentTransition(.numericText())
                .animation(.interpolatingSpring, value: usdValue)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(16)
        .background(background)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 16)
            .inset(by: 0.5)
            .fill(gradient)
            .stroke(bannerTint.opacity(0.17), lineWidth: 1)
            .overlay(logo, alignment: .topTrailing)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Provider badge centered inside two concentric rings, mirroring the Figma
    /// "Frame 1000005808" motif. Drawn in SwiftUI (rings as strokes) so it
    /// composites cleanly over the gradient instead of baking a dark backplate.
    private var logo: some View {
        ZStack {
            Circle()
                .stroke(bannerTint.opacity(0.5), lineWidth: 1)
                .frame(width: 145, height: 145)

            Circle()
                .stroke(bannerTint.opacity(0.3), lineWidth: 1)
                .frame(width: 119, height: 119)

            Image(logoAsset)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .clipShape(Circle())
        }
        .frame(width: 200, height: 206)
        .offset(x: 40, y: 0)
        .allowsHitTesting(false)
    }

    private var gradient: some ShapeStyle {
        LinearGradient(
            stops: [
                Gradient.Stop(color: bannerTint.opacity(0.09), location: 0),
                Gradient.Stop(color: Color(red: 0.37, green: 0.75, blue: 1).opacity(0), location: 1)
            ],
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.5, y: 1)
        )
    }

    private var tab: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tabTitle)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Rectangle()
                .fill(Theme.colors.primaryAccent4)
                .frame(height: 3)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Figma banner gradient/border base — `#4B4C9D` (a blue-purple), distinct
    /// from the teal used elsewhere on the DeFi tab.
    private var bannerTint: Color {
        Color(red: 0.294, green: 0.298, blue: 0.616)
    }
}

#Preview {
    YieldTopBanner(
        providerName: "Noon",
        usdValue: "$2,240.50",
        logoAsset: "noon-logo",
        tabTitle: "Deposited"
    )
    .padding()
    .frame(maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
