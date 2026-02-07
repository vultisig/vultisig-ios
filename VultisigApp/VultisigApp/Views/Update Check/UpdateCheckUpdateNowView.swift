//
//  MacCheckErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct UpdateCheckUpdateNowView: View {
    let latestVersion: String
    let link: URL

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            updateLogo
            VStack(spacing: 12) {
                updateTitle
                updateDescription
            }
            updateButton
            #if os(macOS)
            downloadViaWebsiteButton
            #endif
            Spacer()
        }
    }

    var updateLogo: some View {
        Image("VultisigLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 72)
            .padding(.bottom, 4)
    }

    var updateTitle: some View {
        Text(NSLocalizedString("newUpdateAvailable", comment: ""))
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .padding(.top, 24)
    }

    var updateDescription: some View {
        Text(latestVersion)
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var updateButton: some View {
        return Link(destination: link) {
            PrimaryButtonView(title: "updateNow")
        }
        .buttonStyle(PrimaryButtonStyle())
        .frame(maxWidth: 160)
    }

    #if os(macOS)
    var downloadViaWebsiteButton: some View {
        PrimaryButton(title: "downloadViaWebsite") {
            NSWorkspace.shared.open(StaticURL.GitHubReleasesURL)
        }
        .frame(maxWidth: 200)
    }
    #endif
}

#Preview {
    UpdateCheckUpdateNowView(latestVersion: "v1.2.2", link: StaticURL.AppStoreVultisigURL)
}
