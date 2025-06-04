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
    @State var expireInCount: Int = 0
    
    var body: some View {
        ZStack {
            Background()
            
            VStack {
                content
                button
            }
        }
    }
    
    var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                pickReferralCode
                separator
                setExpiration
                separator
                choosePayoutAsset
                separator
                summary
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
        ReferralTextField(
            placeholderText: "enterUpto4Characters",
            action: .Clear,
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
    
    var setExpiration: some View {
        VStack(spacing: 8) {
            setExpirationTitle
            setExpirationCounter
        }
    }
    
    var setExpirationTitle: some View {
        Text(NSLocalizedString("setExpiration(inYears)", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var setExpirationCounter: some View {
        HStack {
            decreaseExpirationButton
            expiratingInCounter
            increaseExpirationButton
        }
    }
    
    var decreaseExpirationButton: some View {
        Button {
            
        } label: {
            getExpirationCounterButton(icon: "minus.circle")
        }
    }
    
    var expiratingInCounter: some View {
        getExpirationCounterButton(value: "\(expireInCount)")
    }
    
    var increaseExpirationButton: some View {
        Button {
            
        } label: {
            getExpirationCounterButton(icon: "plus.circle")
        }
    }
    
    var choosePayoutAsset: some View {
        VStack(spacing: 8) {
            choosePayoutAssetTitle
            choosePayoutAssetSelection
        }
    }
    
    var choosePayoutAssetTitle: some View {
        Text(NSLocalizedString("choosePayoutAsset", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body14MontserratMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var choosePayoutAssetSelection: some View {
        HStack {
            Text(NSLocalizedString("select", comment: ""))
                .foregroundColor(.extraLightGray)
            
            Spacer()
            
            Image(systemName: "chevron.forward")
                .foregroundColor(.neutral0)
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
        .padding(1)
    }
    
    var summary: some View {
        VStack(spacing: 16) {
            getCell(title: NSLocalizedString("registrationFee", comment: ""), description1: "10 RUNE", description2: "$12.304")
            getCell(title: NSLocalizedString("costs", comment: ""), description1: "10 RUNE", description2: "$12.304")
        }
    }
    
    var separator: some View {
        Rectangle()
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.02, green: 0.11, blue: 0.23), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.16, green: 0.27, blue: 0.44), location: 0.49),
                        Gradient.Stop(color: Color(red: 0.02, green: 0.11, blue: 0.23), location: 1.00),
                    ],
                    startPoint: UnitPoint(x: 0, y: 0.5),
                    endPoint: UnitPoint(x: 1, y: 0.5)
                )
            )
    }
    
    var button: some View {
        FilledButton(title: "createReferral", textColor: .neutral0, background: .persianBlue400)
            .padding(24)
    }
    
    private func getExpirationCounterButton(icon: String? = nil, value: String? = nil) -> some View {
        ZStack {
            if let icon {
                Image(systemName: icon)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.blue600)
                    .font(.body22BrockmannMedium)
            } else if let value {
                Text(value)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.clear)
                    .font(.body16BrockmannMedium)
            }
        }
        .foregroundColor(.neutral0)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue400, lineWidth: 1)
        )
    }
    
    private func getCell(title: String, description1: String, description2: String) -> some View {
        HStack {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(.extraLightGray)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 0) {
                Text(description1)
                    .foregroundColor(.neutral0)
                
                Text(description2)
                    .foregroundColor(.extraLightGray)
            }
        }
        .font(.body14BrockmannMedium)
    }
}

#Preview {
    CreateReferralView()
}
