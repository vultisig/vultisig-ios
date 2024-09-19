//
//  PHoneCheckUpdateView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

import SwiftUI

struct PhoneCheckUpdateView: View {
    @EnvironmentObject var phoneCheckUpdateViewModel: PhoneCheckUpdateViewModel
    
    var body: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("checkUpdate", comment: ""))
        .onAppear {
            setData()
        }
    }
    
    var main: some View {
        view
    }
    
    var view: some View {
        ZStack {
            if phoneCheckUpdateViewModel.showDetails {
                details
            } else if phoneCheckUpdateViewModel.showError {
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
            if phoneCheckUpdateViewModel.isUpdateAvailable {
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
            .font(.body16MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var tryAgainButton: some View {
        Button {
            setData()
        } label: {
            FilledButton(title: "tryAgain")
        }
        .padding(40)
    }
    
    var appUpToDateMessage: some View {
        MacCheckUpToDateView(currentVersion: "Version " + phoneCheckUpdateViewModel.currentVersionString)
    }
    
    var updateAppMessage: some View {
        MacCheckUpdateNowView(
            latestVersion: "v" + phoneCheckUpdateViewModel.latestVersionString + ".0",
            link: Endpoint.appStoreLink
        )
    }
    
    private func setData() {
        phoneCheckUpdateViewModel.checkForUpdates()
    }
}

#Preview {
    PhoneCheckUpdateView()
        .environmentObject(PhoneCheckUpdateViewModel())
}
