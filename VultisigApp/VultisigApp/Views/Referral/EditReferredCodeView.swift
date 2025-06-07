//
//  EditReferredCodeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-26.
//

import SwiftUI

struct EditReferredCodeView: View {
    @StateObject var referralViewModel: ReferralViewModel
    
    var body: some View {
        ZStack {
            Background()
            container
            
            if referralViewModel.isLoading {
                loader
            }
        }
        .onAppear {
            setData()
        }
    }
    
    var content: some View {
        VStack {
            main
            button
        }
    }
    
    var main: some View {
        ScrollView {
            VStack(spacing: 8) {
                title
                textField
            }
        }
        .foregroundColor(.neutral0)
        .padding(24)
    }
    
    var title: some View {
        Text(NSLocalizedString("useReferralCode", comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.body14BrockmannMedium)
    }
    
    var textField: some View {
        ReferralTextField(
            text: $referralViewModel.referredCode,
            placeholderText: "enterUpto4Characters",
            action: .Paste,
            showError: referralViewModel.showReferralLaunchViewError,
            errorMessage: referralViewModel.referralLaunchViewErrorMessage
        )
    }
    
    var button: some View {
        Button {
            referralViewModel.verifyReferredCode()
        } label: {
            FilledButton(title: "saveReferredCode", textColor: .neutral0, background: .persianBlue400)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
    
    var loader: some View {
        Loader()
    }
    
    private func setData() {
        referralViewModel.referredCode = referralViewModel.savedReferredCode
    }
}

#Preview {
    EditReferredCodeView(referralViewModel: ReferralViewModel())
}
