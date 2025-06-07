//
//  ReferralLaunchView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-29.
//

import SwiftUI

struct ReferralLaunchView: View {
    @State var referralCode: String = ""
    
    @State var showError: Bool = false
    @State var errorMessage: String = ""
    
    var body: some View {
        container
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
    
    var saveButton: some View {
        FilledButton(title: "saveReferral", textColor: .neutral0, background: .blue400)
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
        FilledButton(title: "createNewVault", textColor: .neutral0, background: .persianBlue400)
    }
    
    var textField: some View {
        ReferralTextFieldWithCopy(
            placeholderText: "enterUpto4Characters",
            text: $referralCode,
            showError: $showError,
            errorMessage: $errorMessage
        )
    }
    
    var image: some View {
        Image("ReferralLaunchOverview")
            .resizable()
            .frame(maxWidth: 1024)
            .aspectRatio(contentMode: .fit)
    }
}

#Preview {
    ReferralLaunchView()
}
