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
    
    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            updateLogo
            updateTitle
            updateDescription
            Spacer()
            updateButton
        }
    }
    
    var updateLogo: some View {
        Image(systemName: "arrow.down.circle.dotted")
            .font(Theme.fonts.display)
            .foregroundColor(Theme.colors.textPrimary)
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
        .padding(40)
    }
}

#Preview {
    UpdateCheckUpdateNowView(latestVersion: "v1.2.2", link: StaticURL.AppStoreVultisigURL)
}
