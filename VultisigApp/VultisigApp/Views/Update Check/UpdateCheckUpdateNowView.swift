//
//  MacCheckErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

import SwiftUI

struct UpdateCheckUpdateNowView: View {
    let latestVersion: String
    let link: String
    
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
            .font(.title60MontserratLight)
            .foregroundColor(.neutral0)
    }
    
    var updateTitle: some View {
        Text(NSLocalizedString("newUpdateAvailable", comment: ""))
            .font(.body16MontserratSemiBold)
            .foregroundColor(.neutral0)
            .padding(.top, 24)
    }
    
    var updateDescription: some View {
        Text(latestVersion)
            .font(.body12Montserrat)
            .foregroundColor(.neutral0)
    }
    
    var updateButton: some View {
        return Link(destination: URL(string: link)!) {
            FilledButton(title: "updateNow")
        }
        .padding(40)
    }
}

#Preview {
    UpdateCheckUpdateNowView(latestVersion: "v1.2.2", link: Endpoint.appStoreLink)
}
