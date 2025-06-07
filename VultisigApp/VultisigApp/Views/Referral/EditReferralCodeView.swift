//
//  EditReferralCodeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-26.
//

import SwiftUI

struct EditReferralCodeView: View {
    @State var referralCode: String = ""
    
    @State var showError: Bool = false
    @State var errorMessage: String = ""
    @State var showSuccess: Bool = false
    @State var successMessage: String = ""
    
    var body: some View {
        VStack {
            content
            button
        }
    }
    
    var content: some View {
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
            text: $referralCode,
            placeholderText: "enterUpto4Characters",
            action: .Paste,
            showError: showError,
            errorMessage: errorMessage,
            showSuccess: showSuccess,
            successMessage: successMessage
        )
    }
    
    var button: some View {
        Button {
            
        } label: {
            FilledButton(title: "useReferral", textColor: .neutral0, background: .persianBlue400)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

#Preview {
    EditReferralCodeView()
}
