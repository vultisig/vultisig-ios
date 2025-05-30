//
//  CreateReferralView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-30.
//

import SwiftUI

struct CreateReferralView: View {
    @State var referralCode: String = ""
    
    @State var showError: Bool = false
    @State var errorMessage: String = ""
    
    var body: some View {
        ZStack {
            Background()
            content
        }
    }
    
    var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                pickReferralCode
                
                
            }
            .padding(24)
        }
    }
    
    var pickReferralCode: some View {
        VStack(spacing: 8) {
            pickReferralTitle
            
            HStack(spacing: 8) {
                pickReferralTextfield
                searchButton
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
        ReferralTextFieldWithCopy(
            placeholderText: "enterUpto4Characters",
            text: $referralCode,
            showError: $showError,
            errorMessage: $errorMessage
        )
    }
    
    var searchButton: some View {
        Button {
            
        } label: {
            searchButtonLabel
        }
    }
    
    var searchButtonLabel: some View {
        Text(NSLocalizedString("search", comment: ""))
            .foregroundColor(.lightText)
            .font(.body14BrockmannSemiBold)
            .frame(width: 100, height: 60)
            .background(Color.persianBlue400)
            .cornerRadius(16)
    }
}

#Preview {
    CreateReferralView()
}
