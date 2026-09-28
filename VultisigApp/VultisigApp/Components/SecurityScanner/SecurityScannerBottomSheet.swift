//
//  SecurityScannerBottomSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import SwiftUI
import VultisigUIResources

struct SecurityScannerBottomSheetContent: View {
    let contentStyle: SecurityScannerBottomSheetStyle
    let securityScannerProvider: String?
    let onDismissRequest: () -> Void
    let onContinueAnyway: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: contentStyle.image)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(contentStyle.imageColor)

            VStack(spacing: 12) {
                Text(contentStyle.title)
                    .foregroundStyle(contentStyle.imageColor)
                    .font(Theme.fonts.title2)
                    .multilineTextAlignment(.center)

                Text(contentStyle.description)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)
                    .multilineTextAlignment(.center)
                    .frame(height: 60)
            }

            if let securityScannerProvider = securityScannerProvider {
                HStack(spacing: 4) {
                    Spacer()
                    Text("securityScannerPoweredBy".localized)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .font(Theme.fonts.bodySMedium)
                    VultisigImage(securityScannerProvider)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                }
            }

            VStack(spacing: 8) {
                PrimaryButton(title: "securityScannerContinueGoBack".localized) {
                    onDismissRequest()
                }

                Button("securityScannerContinueAnyway".localized) {
                    onContinueAnyway()
                }
                .frame(height: 42, alignment: .center)
                .foregroundStyle(Theme.colors.textButtonDisabled)
                .font(Theme.fonts.caption10)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }
        }
    }
}

struct SettingsSecurityScannerBottomSheet: View, BottomSheetProperties {
    let onDismissRequest: () -> Void
    let onContinueAnyway: () -> Void
    var body: some View {
        SecurityScannerBottomSheetContent(
            contentStyle: SecurityScannerBottomSheetStyle(
                title: "vaultSettingsSecurityScreenTitleBottomsheet".localized,
                description: "vaultSettingsSecurityScreenContentBottomsheet".localized,
                image: "exclamationmark.circle",
                imageColor: Theme.colors.alertWarning
            ),
            securityScannerProvider: nil,
            onDismissRequest: onDismissRequest,
            onContinueAnyway: onContinueAnyway
        )
    }
}

struct SecurityScannerBottomSheetStyle {
    let title: String
    let description: String
    let image: String
    let imageColor: Color
}
