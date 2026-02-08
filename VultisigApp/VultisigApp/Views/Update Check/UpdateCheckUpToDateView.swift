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
        VStack(spacing: 34) {
            Spacer()
            vultisigLogo
            VStack(spacing: 12) {
                upToDateTitle
                upToDateDescription
            }
            #if os(macOS)
            downloadViaWebsiteButton
            #endif
            Spacer()
        }
    }

    var vultisigLogo: some View {
        Image("VultisigLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 72)
    }

    var upToDateTitle: some View {
        Text(NSLocalizedString("appUpToDate", comment: ""))
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .padding(.top, 24)
    }

    var upToDateDescription: some View {
        Text(currentVersion)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textTertiary)
    }

    #if os(macOS)
    var downloadViaWebsiteButton: some View {
        PrimaryButton(title: "downloadViaWebsite", type: .secondary) {
            openURL(StaticURL.GitHubReleasesURL)
        }
        .frame(maxWidth: 200)
    }
    #endif
}

#Preview {
    UpdateCheckUpToDateView(currentVersion: "v1.0.1")
}
