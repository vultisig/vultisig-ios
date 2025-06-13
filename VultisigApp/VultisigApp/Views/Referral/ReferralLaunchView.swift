//
//  ReferralLaunchView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-29.
//

import SwiftUI

struct ReferralLaunchView: View {
    @ObservedObject var referralViewModel: ReferredViewModel
    
    var body: some View {
        ZStack {
            container
            
            if referralViewModel.isLoading {
                loader
            }
        }
        .alert(isPresented: $referralViewModel.showReferredLaunchViewSuccess) {
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
        Text(NSLocalizedString(referralViewModel.referredLaunchViewErrorMessage, comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.body14BrockmannMedium)
            .foregroundColor(.alertRed)
            .opacity(referralViewModel.showReferredLaunchViewError ? 1 : 0)
    }
    
    var saveButton: some View {
        Button {
            referralViewModel.verifyReferredCode()
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
            CreateReferralView()
        } label: {
            createLabel
        }
    }
    
    var createLabel: some View {
        FilledButton(title: "createReferral", textColor: .neutral0, background: .persianBlue400)
    }
    
    var textField: some View {
        ReferralTextField(
            text: $referralViewModel.referredCode,
            placeholderText: "enterUpto4Characters",
            action: .Paste,
            showError: referralViewModel.showReferredLaunchViewError,
            errorMessage: referralViewModel.referredLaunchViewErrorMessage
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
            if referralViewModel.savedReferredCode.isEmpty {
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
            Text(referralViewModel.savedReferredCode)
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
            EditReferredCodeView(referralViewModel: referralViewModel)
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
            message: Text(NSLocalizedString(referralViewModel.referredLaunchViewSuccessMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
}

#Preview {
    ReferralLaunchView(referralViewModel: ReferredViewModel())
}
