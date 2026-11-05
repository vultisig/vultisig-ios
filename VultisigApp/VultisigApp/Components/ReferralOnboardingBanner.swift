//
//  ReferralOnboardingBanner.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-27.
//

import SwiftUI
import VultisigUIResources

struct ReferralOnboardingBanner: View {
    let onNext: () -> Void
    let onClose: () -> Void

    @State private var contentHeight: CGFloat = 0

    private let minimumSheetHeight: CGFloat = 512
    private let homeIndicatorHeight: CGFloat = 34

    var body: some View {
        ZStack(alignment: .top) {
            Theme.colors.bgSurface1
                .ignoresSafeArea()
            content
            closeButtonContainer
        }
        .presentationDetents([.height(max(minimumSheetHeight, contentHeight + homeIndicatorHeight))])
        .presentationDragIndicator(.visible)
    }

    var content: some View {
        VStack(spacing: 24) {
            image
            title
            description
            button
        }
        .padding(.top, 26)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
        .readSize { contentHeight = $0.height }
    }

    var image: some View {
        VultisigImage("ReferralOnboardingBanner")
            .resizable()
            .frame(width: 241, height: 194)
    }

    var title: some View {
        Group {
            Text(NSLocalizedString("referralOnboardingBannerTitle1", comment: ""))
                .foregroundStyle(Theme.colors.textPrimary) +
            Text(NSLocalizedString("referralOnboardingBannerTitle2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("referralOnboardingBannerTitle3", comment: ""))
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .settingsText(.title2)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 35)
    }

    var description: some View {
        Text("referralOnboardingBannerDescription".localized)
            .settingsText(.bodyS)
            .foregroundStyle(Theme.colors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 35)
    }

    var button: some View {
        PrimaryButton(title: "getStarted", size: .compactSemibold) {
            handleTap()
        }
        .padding(.horizontal, 35)
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
            .foregroundStyle(Theme.colors.textPrimary)
    }

    private func handleTap() {
        onNext()
    }
}

#Preview {
    ReferralOnboardingBanner(onNext: {}, onClose: {})
}
