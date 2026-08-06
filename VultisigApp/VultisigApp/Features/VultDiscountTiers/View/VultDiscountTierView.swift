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

    private let topRadius: CornerRadius = Theme.radius.xl
    /// Deliberately off the scale. The card's 24-top / 20-bottom asymmetry is a
    /// Figma value, not a rounding of one: the footer bar peeks out from under
    /// the bottom edge and the two radii are drawn to sit together.
    private let bottomCornerRadius: CGFloat = 20 // swiftlint:disable:this no_raw_corner_radius
    private let footerRadius: CornerRadius = Theme.radius.xl
    private let footerHeight: CGFloat = 48

    var holdAmountText: String {
        "\(tier.balanceToUnlock.formatForDisplay(skipAbbreviation: true)) $VULT"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            footer
            cardBody
                .clipShape(cardShape)
                .contentShape(cardShape)
        }
        .padding(.bottom, isExpanded ? footerHeight : 0)
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
            .clipShape(Theme.radius.lg.shape)
            .overlay(
                Theme.radius.lg.shape
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

    /// Whether the footer should fire the unlock action on tap. Only tiers the
    /// user can actually buy into (non-active and `canUnlock`) are interactive;
    /// already-covered lower tiers render a non-tappable "✓ Unlocked" label.
    var isUnlockTappable: Bool {
        !isActiveInternal && canUnlock
    }

    /// The full-width gradient footer bar. Active tiers show "✓ Active";
    /// expanded unlockable tiers show a tappable "Unlock Tier"; already-covered
    /// lower tiers show a non-interactive "✓ Unlocked".
    var footer: some View {
        footerContent
            .frame(maxWidth: .infinity, alignment: .bottom)
            .frame(height: footerHeight, alignment: .bottom)
            .padding(.bottom, 14)
            .background(footerGradient)
            .overlay(footerInnerShadow)
            // Both radii below are the CARD's bottom radius, not the footer's
            // own: the bar sits behind `cardBody` and peeks out from under it,
            // so its bottom edge has to trace the edge it emerges from. Written
            // as a literal `20` they were a silent copy — move the card and the
            // footer would have cut across the corner it is meant to follow.
            .clipShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: bottomCornerRadius,
                    bottomTrailingRadius: bottomCornerRadius
                )
            )
            .offset(y: isExpanded ? 48 : 2)
            .overlay(
                RoundedRectangle(cornerRadius: bottomCornerRadius)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
            .onTapGesture {
                if isUnlockTappable {
                    onUnlock()
                }
            }
    }

    @ViewBuilder
    var footerContent: some View {
        if isUnlockTappable {
            Text("unlockTier".localized)
                .font(Theme.fonts.buttonSSemibold)
                .foregroundStyle(Theme.colors.textPrimary)
        } else {
            HStack(spacing: 5) {
                Icon(.check, color: Theme.colors.textPrimary, size: 14)
                Text((isActiveInternal ? "active" : "unlocked").localized)
                    .font(Theme.fonts.buttonSSemibold)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            .transaction { $0.animation = nil }
        }
    }

    @ViewBuilder
    var footerGradient: some View {
        switch tier {
        case .ultimate:
            LinearGradient(
                colors: [Color(hex: "FFC25C"), Color(hex: "0F4594"), Color(hex: "041022")],
                startPoint: .init(x: 1, y: -3),
                endPoint: .init(x: 0, y: 0.5)
            )

        default:
            LinearGradient(
                colors: [tier.secondaryColor, tier.primaryColor],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var footerInnerShadow: some View {
        footerRadius.shape
            .stroke(Color.white.opacity(0.1), lineWidth: 1)
            .blur(radius: 1)
            .mask(
                footerRadius.shape
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
                topLeading: topRadius.points,
                bottomLeading: bottomCornerRadius,
                bottomTrailing: bottomCornerRadius,
                topTrailing: topRadius.points
            ),
            // The top corners come from the token, so the style has to come
            // from it too — a radius on the scale drawn with whatever style the
            // SDK happens to default to is the one pairing that silently stops
            // tracking the design system.
            style: topRadius.style
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
    .background(Theme.colors.bgPrimary)
}
