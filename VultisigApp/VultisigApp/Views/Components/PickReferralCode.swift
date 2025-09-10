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
        return VStack(spacing: 8) {
            pickReferralTitle
            
            HStack(alignment: .top, spacing: 8) {
                pickReferralTextfield
                searchButton
                    .padding(.top, 4)
            }
            
            status
                .animation(.easeInOut, value: referralViewModel.availabilityStatus != nil)
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
            action: .None,
            errorMessage: $referralViewModel.referralAvailabilityErrorMessage,
            showSuccess: referralViewModel.availabilityStatus == .available
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
    
    @ViewBuilder
    var status: some View {
        if let status = referralViewModel.availabilityStatus {
            HStack {
                Text(NSLocalizedString("status", comment: ""))
                    .foregroundColor(Theme.colors.textExtraLight)
                
                Spacer()
                
                Text(status.description)
                    .foregroundColor(status.color)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .cornerRadius(24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Theme.colors.border, lineWidth: 1)
                    )
            }
            .font(Theme.fonts.bodySMedium)
            .padding(.top, 2)
        }
    }
}

#Preview {
    PickReferralCode(referralViewModel: ReferralViewModel())
}
