//
//  PickReferralCode.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-09.
//

import SwiftUI

struct PickReferralCode: View {
    @ObservedObject var referralViewModel: ReferralViewModel
    
    var body: some View {
        let isVisible = referralViewModel.showReferralAvailabilityError || referralViewModel.showReferralAvailabilitySuccess
        
        return VStack(spacing: 8) {
            pickReferralTitle
            
            HStack(spacing: 8) {
                pickReferralTextfield
                searchButton
            }
            
            if isVisible {
                status
                    .animation(.easeInOut, value: isVisible)
            }
        }
    }
    
    var pickReferralTitle: some View {
        Text(NSLocalizedString("pickReferralCode", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var pickReferralTextfield: some View {
        ReferralTextField(
            text: $referralViewModel.referralCode,
            placeholderText: "enter4Characters",
            action: .Clear,
            showError: referralViewModel.showReferralAvailabilityError,
            errorMessage: "",
            showSuccess: referralViewModel.showReferralAvailabilitySuccess,
            isErrorLabelVisible: false
        )
        .onChange(of: referralViewModel.referralCode) { oldValue, newValue in
            referralViewModel.resetReferralData()
        }
    }
    
    var searchButton: some View {
        PrimaryButton(title: "search".localized, size: .small) {
            Task {
                await referralViewModel.verifyReferralCode()
            }
        }
        .frame(maxWidth: 100, maxHeight: 46)
        .disabled(referralViewModel.isLoading)
    }
    
    var status: some View {
        HStack {
            Text(NSLocalizedString("status", comment: ""))
                .foregroundColor(Theme.colors.textExtraLight)
            
            Spacer()
            
            statusCapsule
        }
        .font(Theme.fonts.bodySMedium)
        .padding(.top, 2)
    }
    
    var statusCapsule: some View {
        Group {
            if referralViewModel.showReferralAvailabilitySuccess {
                Text(NSLocalizedString("available", comment: ""))
                    .foregroundColor(Theme.colors.alertInfo)
            } else {
                Text(NSLocalizedString(referralViewModel.referralAvailabilityErrorMessage, comment: ""))
                    .foregroundColor(Theme.colors.alertError)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }
}

#Preview {
    PickReferralCode(referralViewModel: ReferralViewModel())
}
