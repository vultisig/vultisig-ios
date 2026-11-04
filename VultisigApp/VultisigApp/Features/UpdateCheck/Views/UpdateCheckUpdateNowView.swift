//
//  MacCheckErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

import SwiftUI

struct UpdateCheckUpdateNowView: View {
    let latestVersion: String
    let link: URL

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            UpdateCheckLogo()
            VStack(spacing: UpdateCheckLayout.titleToVersion) {
                updateTitle
                updateDescription
            }
            .padding(.top, UpdateCheckLayout.logoToTitle)
            updateButton
                .padding(.top, UpdateCheckLayout.versionToButton)
            #if os(macOS)
            downloadViaGitHubButton
                .padding(.top, UpdateCheckLayout.versionToButton)
            #endif
            Spacer()
        }
        .padding(.top, UpdateCheckLayout.topInset)
    }

    var updateTitle: some View {
        Text(NSLocalizedString("newUpdateAvailable", comment: ""))
            .settingsText(.buttonRegular)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
    }

    var updateDescription: some View {
        Text(latestVersion)
            .settingsText(.buttonS)
            .foregroundStyle(Theme.colors.textTertiary)
    }

    var updateButton: some View {
        Link(destination: link) {
            Text("updateApp".localized)
        }
        .buttonStyle(SettingsCTAButtonStyle(width: .hug))
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

#Preview {
    UpdateCheckUpdateNowView(latestVersion: "v1.2.2", link: StaticURL.AppStoreVultisigURL)
}
