//
//  ReferralLaunchView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-29.
//

import SwiftUI

struct ReferralLaunchView: View {
    @ObservedObject var referralViewModel: ReferralViewModel
    
    var body: some View {
        ZStack {
            container
            
            if referralViewModel.isLoading {
                loader
            }
        }
    }
    
    var main: some View {
        VStack(spacing: 16) {
            Spacer()
            image
            Spacer()
            referralCodeTextField
            saveButton
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
        Text(NSLocalizedString(referralViewModel.referralLaunchViewErrorMessage, comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.body14BrockmannMedium)
            .foregroundColor(.alertRed)
            .opacity(referralViewModel.showReferralLaunchViewError ? 1 : 0)
    }
    
    var saveButton: some View {
        Button {
            referralViewModel.verifyReferredCode()
        } label: {
            saveLabel
        }
    }
    
    var saveLabel: some View {
        OutlineButton(title: "saveReferral", textColor: .solidWhite, gradient: .solidBlue)
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
        FilledButton(title: "createReferral", textColor: .neutral0, background: .persianBlue400)
    }
    
    var textField: some View {
        ReferralTextField(
            text: $referralViewModel.referredCode,
            placeholderText: "enterUpto4Characters",
            action: .Paste,
            showError: referralViewModel.showReferralLaunchViewError,
            errorMessage: referralViewModel.referralLaunchViewErrorMessage,
            showSuccess: referralViewModel.showReferralLaunchViewSuccess,
            successMessage: referralViewModel.referralLaunchViewSuccessMessage
        )
    }
    
    var image: some View {
        Image("ReferralLaunchOverview")
            .resizable()
            .frame(maxWidth: 1024)
            .aspectRatio(contentMode: .fit)
    }
    
    var loader: some View {
        Loader()
    }
}

#Preview {
    ReferralLaunchView(referralViewModel: ReferralViewModel())
}
