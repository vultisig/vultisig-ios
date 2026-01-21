//
//  ReferralOnboardingBanner.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-27.
//

import SwiftUI

struct ReferralOnboardingBanner: View {
    let onNext: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Background()
            content
            closeButtonContainer
        }
    }

    var content: some View {
        VStack(spacing: 12) {
            image
            Spacer()
            title
            button
        }
        .frame(height: 400)
        .padding(.horizontal, 24)
    }

    var image: some View {
        Image("ReferralOnboardingBanner")
            .resizable()
            .frame(width: 240, height: 194)
            .padding(.bottom, 12)
    }

    var title: some View {
        Group {
            Text(NSLocalizedString("referralOnboardingBannerTitle1", comment: ""))
                .foregroundColor(Theme.colors.textPrimary) +
            Text(NSLocalizedString("referralOnboardingBannerTitle2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("referralOnboardingBannerTitle3", comment: ""))
                .foregroundColor(Theme.colors.textPrimary)
        }
        .font(Theme.fonts.title2)
        .multilineTextAlignment(.center)
    }

    var button: some View {
        PrimaryButton(title: "next") {
            handleTap()
        }
        .padding(.bottom, 24)
        .padding(.top, 12)
    }

    var closeButtonContainer: some View {
        HStack {
            Spacer()
            VStack {
                closeButton

                Spacer()
            }
        }
    }

    var closeButton: some View {
        Button {
            onClose()
        } label: {
            closeLabel
        }
        .buttonStyle(.plain)
        .padding(24)
    }

    var closeLabel: some View {
        Image(systemName: "xmark")
            .font(Theme.fonts.title2)
            .foregroundColor(Theme.colors.textPrimary)
    }

    private func handleTap() {
        onNext()
    }
}

#Preview {
    ReferralOnboardingBanner(onNext: {}, onClose: {})
}
