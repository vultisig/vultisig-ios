//
//  MacCheckUpdateView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

import SwiftUI

struct MacCheckUpdateView: View {
    @EnvironmentObject var checkUpdateViewModel: CheckUpdateViewModel
    
    var body: some View {
        ZStack {
            Background()
            main
        }
        .onAppear {
            setData()
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "checkUpdate")
            .padding(.bottom, 8)
    }
    
    var view: some View {
        ZStack {
            if checkUpdateViewModel.showDetails {
                details
            } else if checkUpdateViewModel.showError {
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
            if checkUpdateViewModel.isUpdateAvailable {
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
        MacCheckUpToDateView()
    }
    
    var updateAppMessage: some View {
        MacCheckUpdateNowView()
    }
    
    private func setData() {
        checkUpdateViewModel.checkForUpdates()
    }
}

#Preview {
    MacCheckUpdateView()
        .environmentObject(CheckUpdateViewModel())
}
