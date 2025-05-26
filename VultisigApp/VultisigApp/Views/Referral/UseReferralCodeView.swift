//
//  UseReferralCodeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-26.
//

import SwiftUI

struct UseReferralCodeView: View {
    @State var referralCode: String = ""
    
    @State var showError: Bool = false
    @State var errorMessage: String = ""
    
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
                
                if showError {
                    errorText
                }
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
        HStack {
            TextField(NSLocalizedString("enterUpto4Characters", comment: ""), text: $referralCode)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .submitLabel(.done)
            
            copyButton
        }
        .frame(height: 56)
        .font(.body16BrockmannMedium)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(showError ? Color.invalidRed : Color.blue200, lineWidth: 1)
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .borderlessTextFieldStyle()
        .padding(1)
    }
    
    var copyButton: some View {
        Button {
            handleCopyCode()
        } label: {
            Image(systemName: "square.on.square")
        }
    }
    
    var button: some View {
        Button {
            
        } label: {
            FilledButton(title: "useReferral", textColor: .neutral0, background: .persianBlue400)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
    
    var errorText: some View {
        Text(NSLocalizedString(errorMessage, comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.body14BrockmannMedium)
            .foregroundColor(.invalidRed)
    }
    
    private func handleCopyCode() {
        errorMessage = "sameUseReferralCodeErrorMessage"
        showError = true
    }
}

#Preview {
    UseReferralCodeView()
}
