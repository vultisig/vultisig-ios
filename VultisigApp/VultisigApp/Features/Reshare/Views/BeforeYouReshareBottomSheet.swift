//
//  BeforeYouReshareBottomSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/07/2026.
//

import SwiftUI

/// Pre-flight warning shown before starting a reshare: old backups become
/// invalid and enough current co-signers to meet the threshold must be online.
struct BeforeYouReshareBottomSheet: View, BottomSheetProperties {
    let onContinue: () -> Void

    var bgColor: Color? { Theme.colors.bgPrimary }

    var body: some View {
        VStack(spacing: 10) {
            header
            warningCards
                .padding(.top, 12)
                .padding(.bottom, 24)
            PrimaryButton(title: "iUnderstand", action: onContinue)
        }
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    var header: some View {
        VStack(spacing: 12) {
            Text("beforeYouReshare".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)

            Text("beforeYouReshareSubtitle".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(maxWidth: 257)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
    }

    var warningCards: some View {
        VStack(spacing: 10) {
            ReshareWarningCard(
                icon: .fileTree,
                title: "newBackupsCreatedTitle".localized,
                subtitle: "newBackupsCreatedDescription".localized
            )

            ReshareWarningCard(
                icon: .trafficCone,
                title: "oldBackupsOnlyWorkTogetherTitle".localized,
                subtitle: "oldBackupsOnlyWorkTogetherDescription".localized
            )

            ReshareWarningCard(
                icon: .circles5,
                title: "requiredCosignersOnlineTitle".localized,
                subtitle: "requiredCosignersOnlineDescription".localized
            )
        }
    }
}

private struct ReshareWarningCard: View {
    let icon: ImageResource
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(
                icon,
                color: Theme.colors.alertWarning,
                size: 24
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Theme.fonts.subtitle)
                    .foregroundStyle(Theme.colors.textPrimary)

                Text(subtitle)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(Theme.colors.bgSurface1)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    BeforeYouReshareBottomSheet(onContinue: {})
        .background(Theme.colors.bgPrimary)
}
