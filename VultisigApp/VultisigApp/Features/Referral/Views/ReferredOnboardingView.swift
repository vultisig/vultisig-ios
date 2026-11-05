//
//  ReferredOnboardingView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-27.
//

import SwiftUI

struct ReferredOnboardingView: View {
    @Environment(\.router) var router

    var body: some View {
        Screen {
            VStack {
                ScrollView {
                    StepsAnimationView(title: "howItWorks".localized, steps: 4) { animationCell(index: $0)
                    } header: {
                        animationHeader
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                }

                button
            }
            .background(SettingsGlowBackground(tint: .referral, verticalOffset: 0))
        }
        .screenTitle("referral".localized)
    }

    var button: some View {
        PrimaryButton(title: "next", size: .compactSemibold) {
            router.navigate(to: ReferralRoute.initial)
        }
    }

    @ViewBuilder
    func animationCell(index: Int) -> some View {
        switch index {
        case 0:
            cellView(
                icon: .keyboardFilled,
                title: "referralOnboardingTitle1",
                description: "referralOnboardingDescription1"
            )
        case 1:
            cellView(
                icon: .shareUpRight2,
                title: "referralOnboardingTitle2",
                description: "referralOnboardingDescription2"
            )
        case 2:
            cellView(
                icon: .trophy,
                title: "referralOnboardingTitle3",
                description: "referralOnboardingDescription3"
            )
        case 3:
            cellView(
                icon: .usersFilled,
                title: "referralOnboardingTitle4",
                description: "referralOnboardingDescription4"
            )
        default:
            EmptyView()
        }
    }

    func cellView(icon: ImageResource, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Icon(icon, color: Theme.colors.primaryAccent4, size: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString(title, comment: ""))
                    .settingsText(.footnote)
                    .foregroundStyle(Theme.colors.textPrimary)

                Text(NSLocalizedString(description, comment: ""))
                    .settingsText(.captionSmall)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var animationHeader: some View {
        HStack(spacing: 8) {
            Icon(.megaphone, color: Theme.colors.alertInfo, size: 16)
            Text(NSLocalizedString("referralProgram", comment: ""))
                .foregroundStyle(Theme.colors.textTertiary)
                .settingsText(.caption)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSurface1)
        // The trailing edge is a capsule end cap: `32` already exceeded half the
        // row's height, so both corners were clamped and the edge rendered fully
        // round. `pill` says that, and clamps to the same shape — and keeps
        // saying it at accessibility text sizes, where the literal would have
        // stopped clamping once the symbol pushed the row past 64pt. Rounding
        // each corner separately means this cannot use the token's `shape`, so
        // the style is carried across by hand — as the list and banner masks do.
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: Theme.radius.pill.points,
                topTrailingRadius: Theme.radius.pill.points,
                style: Theme.radius.pill.style
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: Theme.radius.pill.points,
                topTrailingRadius: Theme.radius.pill.points,
                style: Theme.radius.pill.style
            )
            .inset(by: 1)
            .stroke(Theme.colors.borderLight, lineWidth: 2)
        )
        .offset(x: -2)
    }
}

#Preview {
    ReferredOnboardingView()
}
