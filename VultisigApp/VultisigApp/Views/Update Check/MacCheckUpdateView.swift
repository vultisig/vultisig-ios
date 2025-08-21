//
//  MacCheckUpdateView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

import SwiftUI

struct MacCheckUpdateView: View {
    @EnvironmentObject var macCheckUpdateViewModel: MacCheckUpdateViewModel
    
    var body: some View {
        Screen(title: "checkUpdate".localized) {
            view
                .background(
                    Ellipse()
                        .fill(Color(red: 0.2, green: 0.9, blue: 0.75))
                        .aspectRatio(contentMode: .fit)
                        .opacity(0.2)
                        .blur(radius: 120)
                )
        }
        .onAppear {
            setData()
        }
    }
    
    var view: some View {
        ZStack {
            if macCheckUpdateViewModel.showDetails {
                details
            } else if macCheckUpdateViewModel.showError {
                errorMessage
            } else {
                loader
            }
        }
    }
    
    var errorMessage: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "somethingWentWrongTryAgain", width: 300)
            Spacer()
            tryAgainButton
        }
    }
    
    var details: some View {
        ZStack {
            if macCheckUpdateViewModel.isUpdateAvailable {
                updateAppMessage
            } else {
                appUpToDateMessage
            }
        }
    }
    
    var loader: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
            checkUpdateLabel
            Spacer()
        }
    }
    
    var checkUpdateLabel: some View {
        Text(NSLocalizedString("checkingForUpdate", comment: ""))
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }
    
    var tryAgainButton: some View {
        PrimaryButton(title: "tryAgain") {
            setData()
        }
        .padding(40)
    }
    
    var appUpToDateMessage: some View {
        UpdateCheckUpToDateView(currentVersion: macCheckUpdateViewModel.currentVersion)
    }
    
    var updateAppMessage: some View {
        let url = Endpoint.githubMacDownloadBase + macCheckUpdateViewModel.latestVersionBase + macCheckUpdateViewModel.latestPackageName
        
        return UpdateCheckUpdateNowView(
            latestVersion: macCheckUpdateViewModel.latestVersion,
            link: URL(string: url)!
        )
    }
    
    private func setData() {
        macCheckUpdateViewModel.checkForUpdates()
    }
}

#Preview {
    MacCheckUpdateView()
        .environmentObject(MacCheckUpdateViewModel())
}
