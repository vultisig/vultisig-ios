//
//  PickReferralCode.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-09.
//

import SwiftUI

struct PickReferralCode: View {
    @ObservedObject var referralViewModel: ReferredViewModel
    
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
            .foregroundColor(.neutral0)
            .font(.body14MontserratMedium)
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
    }
    
    var searchButton: some View {
        Button {
            referralViewModel.verifyReferralCode()
        } label: {
            searchButtonLabel
        }
    }
    
    var searchButtonLabel: some View {
        ZStack {
            if referralViewModel.isLoading {
                ProgressView()
            } else {
                Text(NSLocalizedString("search", comment: ""))
                    .foregroundColor(.lightText)
                    .font(.body14BrockmannSemiBold)
            }
        }
        .frame(width: 100, height: 60)
        .background(Color.persianBlue400)
        .cornerRadius(16)
    }
    
    var status: some View {
        HStack {
            Text(NSLocalizedString("status", comment: ""))
                .foregroundColor(.extraLightGray)
            
            Spacer()
            
            statusCapsule
        }
        .font(.body14MontserratMedium)
        .padding(.top, 2)
    }
    
    var statusCapsule: some View {
        Group {
            if referralViewModel.showReferralAvailabilitySuccess {
                Text(NSLocalizedString("available", comment: ""))
                    .foregroundColor(.alertTurquoise)
            } else {
                Text(NSLocalizedString(referralViewModel.referralAvailabilityErrorMessage, comment: ""))
                    .foregroundColor(.alertRed)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.blue200, lineWidth: 1)
        )
    }
}

#Preview {
    PickReferralCode(referralViewModel: ReferredViewModel())
}
