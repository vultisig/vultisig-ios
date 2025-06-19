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
            orSeparator
            createButton
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
        Text(NSLocalizedString("useReferralCode", comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.body14BrockmannMedium)
            .foregroundColor(.neutral0)
    }
    
    var errorText: some View {
        Text(NSLocalizedString(referredViewModel.referredLaunchViewErrorMessage, comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.body14BrockmannMedium)
            .foregroundColor(.alertRed)
            .opacity(referredViewModel.showReferredLaunchViewError ? 1 : 0)
    }
    
    var saveButton: some View {
        Button {
            referredViewModel.verifyReferredCode(savedGeneratedReferralCode: referralViewModel.savedGeneratedReferralCode)
        } label: {
            saveLabel
        }
    }
    
    var saveLabel: some View {
        OutlineButton(title: "saveReferredCode", textColor: .solidWhite, gradient: .solidBlue)
    }
    
    var orSeparator: some View {
        HStack(spacing: 16) {
            separator
            
            Text(NSLocalizedString("or", comment: "").uppercased())
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
            
            separator
        }
    }
    
    var separator: some View {
        Separator()
            .opacity(0.2)
    }
    
    var createButton: some View {
        NavigationLink {
            CreateReferralView(referralViewModel: referralViewModel)
        } label: {
            createLabel
        }
    }
    
    var createLabel: some View {
        FilledButton(title: "createReferral", textColor: .neutral0, background: .persianBlue400)
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
        .font(.body16BrockmannMedium)
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
        NavigationLink {
            EditReferredCodeView(referredViewModel: referredViewModel, referralViewModel: referralViewModel)
        } label: {
            editLabel
        }
    }
    
    var editLabel: some View {
        OutlineButton(title: "editReferredCode", textColor: .solidWhite, gradient: .solidBlue)
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
}

#Preview {
    ReferralLaunchView(referredViewModel: ReferredViewModel(), referralViewModel: ReferralViewModel())
}
