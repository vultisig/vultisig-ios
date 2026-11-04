//
//  MacCheckUpToDateView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

import SwiftUI

struct UpdateCheckUpToDateView: View {
    let currentVersion: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: UpdateCheckLayout.logoToTitle) {
            UpdateCheckLogo()
            VStack(spacing: UpdateCheckLayout.titleToVersion) {
                upToDateTitle
                upToDateDescription
            }
            #if os(macOS)
            downloadViaGitHubButton
            #endif
            Spacer()
        }
        .padding(.top, UpdateCheckLayout.topInset)
    }

    var upToDateTitle: some View {
        Text(NSLocalizedString("appUpToDate", comment: ""))
            .settingsText(.buttonRegular)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
    }

    var upToDateDescription: some View {
        Text(currentVersion)
            .settingsText(.buttonS)
            .foregroundStyle(Theme.colors.textTertiary)
    }

    #if os(macOS)
    var downloadViaGitHubButton: some View {
        PrimaryButton(title: "downloadViaGitHub", type: .secondary) {
            openURL(StaticURL.GitHubReleasesURL)
        }
        .frame(maxWidth: 200)
    }
    #endif
}

/// Spacing shared by the up to date and update available states, so the logo
/// and text stay put when the button appears.
enum UpdateCheckLayout {
    static let topInset: CGFloat = 186
    static let glowOffset: CGFloat = -59.5
    static let logoToTitle: CGFloat = 27.5
    static let titleToVersion: CGFloat = 12
    static let versionToButton: CGFloat = 30
}

/// The app tile the update states lead with.
struct UpdateCheckLogo: View {
    private static let side: CGFloat = 74.5
    private static let radius: CGFloat = 23.84
    private static let markSide: CGFloat = 41.72

    var body: some View {
        RoundedRectangle(cornerRadius: Self.radius)
            .fill(
                LinearGradient(
                    colors: [Theme.colors.primaryAccent4, Color(hex: "0D39B1")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .shadow(.inner(color: .white.opacity(0.35), radius: 0.75, y: 1.49))
            )
            .frame(width: Self.side, height: Self.side)
            .overlay {
                Icon(.vultisigMark, color: nil, size: Self.markSide)
            }
    }
}

#Preview {
    UpdateCheckUpToDateView(currentVersion: "v1.0.1")
}
