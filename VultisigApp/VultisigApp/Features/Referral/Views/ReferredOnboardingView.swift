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
                }

                button
            }
            .background(shadow)
        }
        .screenTitle("referral".localized)
    }

    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(Theme.colors.alertInfo)
            .opacity(0.05)
            .blur(radius: 20)
    }

    var button: some View {
        PrimaryButton(title: "getStarted") {
            router.navigate(to: ReferralRoute.initial)
        }
    }

    @ViewBuilder
    func animationCell(index: Int) -> some View {
        switch index {
        case 0:
            cellView(
                icon: "dots.and.line.vertical.and.cursorarrow.rectangle",
                title: "referralOnboardingTitle1",
                description: "referralOnboardingDescription1"
            )
        case 1:
            cellView(
                icon: "shareplay",
                title: "referralOnboardingTitle2",
                description: "referralOnboardingDescription2"
            )
        case 2:
            cellView(
                icon: "trophy",
                title: "referralOnboardingTitle3",
                description: "referralOnboardingDescription3"
            )
        case 3:
            cellView(
                icon: "person.badge.shield.checkmark",
                title: "referralOnboardingTitle4",
                description: "referralOnboardingDescription4"
            )
        default:
            EmptyView()
        }
    }

    func cellView(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Theme.colors.primaryAccent4)
                .font(Theme.fonts.bodyLMedium)

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString(title, comment: ""))
                    .font(Theme.fonts.bodySMedium)

                Text(NSLocalizedString(description, comment: ""))
                    .font(Theme.fonts.caption10)
            }
            .foregroundColor(Theme.colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var animationHeader: some View {
        HStack {
            Image(systemName: "horn")
                .foregroundColor(Theme.colors.alertInfo)
            Text(NSLocalizedString("referralProgram", comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSurface1)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 32,
                topTrailingRadius: 32
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 32,
                topTrailingRadius: 32
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
