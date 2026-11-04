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
            if let securityScannerProvider = securityScannerProvider {
                HStack(spacing: 4) {
                    Text("securityScannerPoweredBy".localized)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .settingsText(.caption)
                    VultisigImage(securityScannerProvider)
                        .frame(width: Self.providerLogoSize.width, height: Self.providerLogoSize.height)
                }
            }

            SecurityWarningBadge(tint: contentStyle.imageColor)

            VStack(spacing: 12) {
                Text(contentStyle.title)
                    .foregroundStyle(contentStyle.imageColor)
                    .settingsText(.title2)
                    .multilineTextAlignment(.center)

                Text(contentStyle.description)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .settingsText(.bodyS)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                SettingsCTAButton(title: "securityScannerContinueGoBack", width: .fill) {
                    onDismissRequest()
                }

                Button {
                    onContinueAnyway()
                } label: {
                    Text("securityScannerContinueAnyway".localized)
                        .settingsText(.captionSmall)
                }
                .frame(height: 42, alignment: .center)
                .foregroundStyle(Theme.colors.textButtonDisabled)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }
        }
    }

    private static let providerLogoSize = CGSize(width: 52, height: 9)
}

/// The ringed warning badge at the top of the on-chain security sheet.
private struct SecurityWarningBadge: View {
    let tint: Color

    private static let size = CGSize(width: 48, height: 49)
    private static let ringDiameter: CGFloat = 43
    private static let glowSize = CGSize(width: 13.3, height: 6.7)
    private static let glowBlur: CGFloat = 7.7
    private static let glyphSize: CGFloat = 16

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "03132C"))
                .frame(width: Self.ringDiameter, height: Self.ringDiameter)
            Rectangle()
                .fill(tint)
                .frame(width: Self.glowSize.width, height: Self.glowSize.height)
                .blur(radius: Self.glowBlur)
            Circle()
                .stroke(.white.opacity(0.1), lineWidth: 2)
                .frame(width: Self.ringDiameter, height: Self.ringDiameter)
            Icon(.circleWarning, color: tint, size: Self.glyphSize)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

struct SettingsSecurityScannerBottomSheet: View, BottomSheetProperties {
    let onDismissRequest: () -> Void
    let onContinueAnyway: () -> Void

    var bgColor: Color? { Theme.colors.bgPrimary }
    var usesSystemGrabber: Bool { true }

    var body: some View {
        SecurityScannerBottomSheetContent(
            contentStyle: SecurityScannerBottomSheetStyle(
                title: "vaultSettingsSecurityScreenTitleBottomsheet".localized,
                description: "vaultSettingsSecurityScreenContentBottomsheet".localized,
                imageColor: Theme.colors.alertWarning
            ),
            securityScannerProvider: "blockaid",
            onDismissRequest: onDismissRequest,
            onContinueAnyway: onContinueAnyway
        )
    }
}

struct SecurityScannerBottomSheetStyle {
    let title: String
    let description: String
    let imageColor: Color
}
