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
        Screen(title: "checkUpdate".localized) {
            view.background(BlurredBackground())
        }
        .onAppear {
            setData()
        }
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
        UpdateCheckUpToDateView(currentVersion: phoneCheckUpdateViewModel.currentVersionString)
    }

    var updateAppMessage: some View {
        UpdateCheckUpdateNowView(
            latestVersion: phoneCheckUpdateViewModel.latestVersionString,
            link: StaticURL.AppStoreVultisigURL
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
