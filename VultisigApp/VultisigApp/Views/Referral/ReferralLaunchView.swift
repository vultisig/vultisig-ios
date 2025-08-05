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
        ZStack {
            container
            
            if referredViewModel.isLoading {
                loader
            }
        }
        .onAppear {
            referralViewModel.resetAllData()
        }
        .alert(isPresented: $referredViewModel.showReferredLaunchViewSuccess) {
            alert
        }
    }
    
    var main: some View {
        VStack(spacing: 16) {
            Spacer()
            image
            Spacer()
            referredContent
            
            if referralViewModel.savedGeneratedReferralCode.isEmpty {
                orSeparator
                createTitle
                createButton
            } else {
                separator
                referralTitle
                referralCopyTextField
            }
        }
        .padding(24)
    }
    
    var referralCodeTextField: some View {
        VStack(spacing: 8) {
            title
            textField
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("addYourFriendsCode", comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(.neutral0)
    }
    
    var errorText: some View {
        Text(NSLocalizedString(referredViewModel.referredLaunchViewErrorMessage, comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(.alertRed)
            .opacity(referredViewModel.showReferredLaunchViewError ? 1 : 0)
    }
    
    var saveButton: some View {
        PrimaryButton(title: "saveReferredCode", type: .secondary) {
            referredViewModel.verifyReferredCode(savedGeneratedReferralCode: referralViewModel.savedGeneratedReferralCode)
        }
    }
    
    var orSeparator: some View {
        HStack(spacing: 16) {
            separator
            
            Text(NSLocalizedString("or", comment: "").uppercased())
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(.neutral0)
            
            separator
        }
    }
    
    var createTitle: some View {
        Text(NSLocalizedString("createYourCodeAndEarn", comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(.neutral0)
    }
    
    var separator: some View {
        Separator()
            .opacity(0.2)
    }
    
    var createButton: some View {
        PrimaryNavigationButton(title: "createReferral") {
            CreateReferralView(referralViewModel: referralViewModel)
        }
    }
    
    var textField: some View {
        ReferralTextField(
            text: $referredViewModel.referredCode,
            placeholderText: "enterUpto4Characters",
            action: .Paste,
            showError: referredViewModel.showReferredLaunchViewError,
            errorMessage: referredViewModel.referredLaunchViewErrorMessage
        )
    }
    
    var image: some View {
        Image("ReferralLaunchOverview")
            .resizable()
            .frame(maxWidth: 1024)
            .aspectRatio(contentMode: .fit)
    }
    
    var referredContent: some View {
        VStack(spacing: 16) {
            if referredViewModel.savedReferredCode.isEmpty {
                referralCodeTextField
                saveButton
            } else {
                referralCodeText
                editButton
            }
        }
    }
    
    var referralCodeText: some View {
        HStack {
            Text(referredViewModel.savedReferredCode)
            Spacer()
        }
        .foregroundColor(.neutral0)
        .colorScheme(.dark)
        .frame(height: 56)
        .font(Theme.fonts.bodyMMedium)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue200, lineWidth: 1)
        )
        .autocorrectionDisabled()
        .borderlessTextFieldStyle()
        .padding(1)
    }
    
    var editButton: some View {
        PrimaryNavigationButton(title: "editReferredCode", type: .secondary) {
            EditReferredCodeView(referredViewModel: referredViewModel, referralViewModel: referralViewModel)
        }
    }
    
    var loader: some View {
        Loader()
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString("success", comment: "")),
            message: Text(NSLocalizedString(referredViewModel.referredLaunchViewSuccessMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    var referralTitle: some View {
        Text(NSLocalizedString("yourReferralCode", comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(.neutral0)
    }
    
    var referralCopyTextField: some View {
        ReferralTextField(
            text: $referralViewModel.savedGeneratedReferralCode,
            placeholderText: "",
            action: .Copy,
            showError: false,
            errorMessage: "",
            isDisabled: true
        )
    }
}

#Preview {
    ReferralLaunchView(referredViewModel: ReferredViewModel(), referralViewModel: ReferralViewModel())
}
