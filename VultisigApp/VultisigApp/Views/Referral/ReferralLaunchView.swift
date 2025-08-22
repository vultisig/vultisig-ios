//
//  ReferralLaunchView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-29.
//

import SwiftUI

struct ReferralLaunchView: View {
    @ObservedObject var referredViewModel: ReferredViewModel
    @ObservedObject var referralViewModel: ReferralViewModel
    
    var body: some View {
        Screen(title: "vultisig-referrals".localized) {
            main
        }
        .overlay(referredViewModel.isLoading ? Loader() : nil)
        .onAppear {
            referralViewModel.resetAllData()
        }
        .alert(isPresented: $referredViewModel.showReferredLaunchViewSuccess) {
            alert
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
            Spacer()
            image
            Spacer()
            
            VStack(spacing: 16) {
                referredContent
                orSeparator
                referralContent
            }
        }
    }
    
    var errorText: some View {
        Text(NSLocalizedString(referredViewModel.referredLaunchViewErrorMessage, comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.alertError)
            .opacity(referredViewModel.showReferredLaunchViewError ? 1 : 0)
    }
    
    var orSeparator: some View {
        HStack(spacing: 16) {
            separator
            
            Text(NSLocalizedString("or", comment: "").uppercased())
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
            
            separator
        }
    }
    
    var separator: some View {
        Separator()
            .opacity(0.2)
    }
    
    var image: some View {
        Image("ReferralLaunchOverview")
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
    
    var referredContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                HighlightedText(
                    localisedKey: "referredSaveOnSwaps",
                    highlightedText: "10%"
                ) {
                    $0.font = Theme.fonts.bodySMedium
                    $0.foregroundColor = Theme.colors.textPrimary
                } highlightedTextStyle: {
                    $0.foregroundColor = Theme.colors.primaryAccent4
                }

                referredTextField
            }

            if referredViewModel.hasReferredCode {
                editButton
            } else {
                saveButton
            }
        }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("success", comment: "")),
            message: Text(NSLocalizedString(referredViewModel.referredLaunchViewSuccessMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
}

// MARK: - Referred

private extension ReferralLaunchView {
    var saveButton: some View {
        PrimaryButton(title: "saveReferredCode", type: .secondary) {
            Task { @MainActor in
                await referredViewModel.verifyReferredCode(savedGeneratedReferralCode: referralViewModel.savedGeneratedReferralCode)
            }
        }
    }
    
    var editButton: some View {
        PrimaryNavigationButton(title: "editReferredCode", type: .secondary) {
            EditReferredCodeView(referredViewModel: referredViewModel, referralViewModel: referralViewModel)
        }
    }
    
    var referredTextField: some View {
        ReferralTextField(
            text: $referredViewModel.referredCode,
            placeholderText: "enterUpto4Characters",
            action: .Paste,
            showError: referredViewModel.showReferredLaunchViewError,
            errorMessage: referredViewModel.referredLaunchViewErrorMessage
        )
    }
}

// MARK: - Referral

private extension ReferralLaunchView {
    var referralContent: some View {
        VStack(spacing: 16) {
            referralTitle
            
            if referralViewModel.hasReferralCode {
                createReferralButton
            } else {
                editReferralButton
            }
        }
    }
    
    var referralTitle: some View {
        HighlightedText(
            localisedKey: "createYourCodeAndEarn",
            highlightedText: "20%"
        ) {
            $0.font = Theme.fonts.bodySMedium
            $0.foregroundColor = Theme.colors.textPrimary
        } highlightedTextStyle: {
            $0.foregroundColor = Theme.colors.primaryAccent4
        }
        .multilineTextAlignment(.center)
    }
    
    var createReferralButton: some View {
        PrimaryNavigationButton(title: "createReferral") {
            ReferralTransactionFlowScreen(referralViewModel: referralViewModel, isEdit: false)
        }
    }
    
    var editReferralButton: some View {
        PrimaryNavigationButton(title: "editReferral") {
            ReferralTransactionFlowScreen(referralViewModel: referralViewModel, isEdit: true)
        }
    }
}

#Preview {
    ReferralLaunchView(referredViewModel: ReferredViewModel(), referralViewModel: ReferralViewModel())
}
