//
//  VultDiscountTierView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/10/2025.
//

import SwiftUI

struct VultDiscountTierView: View {
    let tier: VultDiscountTier
    let isActive: Bool
    let canUnlock: Bool
    var onExpand: () -> Void
    var onUnlock: () -> Void

    @State var isExpanded: Bool = false
    @State var isActiveInternal: Bool = false

    private let topCornerRadius: CGFloat = 24
    private let bottomCornerRadius: CGFloat = 20
    private let footerCornerRadius: CGFloat = 24

    var holdAmountText: String {
        "\(tier.balanceToUnlock.formatForDisplay(skipAbbreviation: true)) $VULT"
    }

    var body: some View {
        VStack(spacing: 0) {
            cardBody
            footer
                .showIf(isExpanded)
        }
        .clipShape(cardShape)
        .contentShape(cardShape)
        .onTapGesture { toggleExpansion() }
        .onLoad { animate(isActive: isActive) }
        .onChange(of: isActive) { _, newValue in
            animate(isActive: newValue)
        }
    }
}

private extension VultDiscountTierView {
    var cardBody: some View {
        VStack(spacing: 12) {
            headerRow

            VStack(spacing: 12) {
                perkPill
                Text("moreComingSoon".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .transition(.verticalGrowAndFade)
            .showIf(isExpanded)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, isExpanded ? 16 : 24)
        .frame(maxWidth: .infinity)
        .background(Theme.colors.bgSurface1)
        .overlay(accentBorder, alignment: .bottom)
    }

    var headerRow: some View {
        HStack(spacing: 12) {
            VultDiscountTierIcon(tier: tier, size: .small)
            Text(tier.name.localized)
                .font(Theme.fonts.subtitle)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer(minLength: 0)
            Text(holdAmountText)
                .font(Theme.fonts.priceBodyS)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    var perkPill: some View {
        Text(tier.discountPerkText)
            .font(Theme.fonts.footnote)
            .foregroundStyle(Theme.colors.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.colors.bgSurface1)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: true)
    }

    /// Tier-colored bottom accent that runs along the collapsed/expanded
    /// card edge. Shown only when the footer bar isn't covering it.
    @ViewBuilder
    var accentBorder: some View {
        accentFill
            .frame(height: 1)
            .showIf(!isExpanded)
    }

    @ViewBuilder
    var accentFill: some View {
        switch tier {
        case .ultimate:
            Image("vult-ultimate-box-overlay")
                .resizable()
        default:
            LinearGradient(
                colors: [tier.primaryColor, tier.secondaryColor],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    /// The full-width gradient footer bar. Active tiers show "✓ Active";
    /// expanded non-active tiers show "Unlock Tier".
    var footer: some View {
        footerContent
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .background(footerGradient)
            .overlay(footerInnerShadow)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isActiveInternal {
                    onUnlock()
                }
            }
    }

    @ViewBuilder
    var footerContent: some View {
        if isActiveInternal {
            HStack(spacing: 5) {
                Icon(named: "check", color: Theme.colors.textPrimary, size: 14)
                Text("active".localized)
                    .font(Theme.fonts.buttonSSemibold)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
        } else {
            Text("unlockTier".localized)
                .font(Theme.fonts.buttonSSemibold)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    @ViewBuilder
    var footerGradient: some View {
        switch tier {
        case .ultimate:
            Image("vult-ultimate-box-overlay")
                .resizable()
        default:
            LinearGradient(
                colors: [tier.secondaryColor, tier.primaryColor],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var footerInnerShadow: some View {
        RoundedRectangle(cornerRadius: footerCornerRadius)
            .stroke(Color.white.opacity(0.1), lineWidth: 1)
            .blur(radius: 1)
            .mask(
                RoundedRectangle(cornerRadius: footerCornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .allowsHitTesting(false)
    }

    var cardShape: some Shape {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: topCornerRadius,
                bottomLeading: bottomCornerRadius,
                bottomTrailing: bottomCornerRadius,
                topTrailing: topCornerRadius
            )
        )
    }

    func toggleExpansion() {
        withAnimation(.interpolatingSpring) {
            isExpanded.toggle()
            if isExpanded {
                onExpand()
            }
        }
    }

    func animate(isActive: Bool) {
        withAnimation(.interpolatingSpring) {
            isActiveInternal = isActive
            if isActive {
                isExpanded = true
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(VultDiscountTier.allCases) { tier in
                VultDiscountTierView(
                    tier: tier,
                    isActive: tier == .gold,
                    canUnlock: tier > .gold
                ) {} onUnlock: {}
            }
        }
        .padding()
    }
}
