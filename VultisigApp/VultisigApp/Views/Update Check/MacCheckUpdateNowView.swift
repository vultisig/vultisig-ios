//
//  MacCheckErrorView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

import SwiftUI

struct MacCheckUpdateNowView: View {
    @EnvironmentObject var checkUpdateViewModel: CheckUpdateViewModel
    
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
        Text(checkUpdateViewModel.latestVersion)
            .font(.body12Montserrat)
            .foregroundColor(.neutral0)
    }
    
    var updateButton: some View {
        let url = Endpoint.githubMacUpdateBase + checkUpdateViewModel.latestVersionBase
        
        return Link(destination: URL(string: url)!) {
            FilledButton(title: "updateNow")
        }
        .padding(40)
    }
}

#Preview {
    MacCheckUpdateNowView()
        .environmentObject(CheckUpdateViewModel())
}
