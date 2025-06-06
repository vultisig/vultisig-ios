//
//  ReferralSendOverviewView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-28.
//

import SwiftUI

struct ReferralSendOverviewView: View {
    @State var isAmountCorrect: Bool = false
    @State var isAddressCorrect: Bool = false
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            summary
            checkboxes
            Spacer()
            button
        }
        .padding(24)
    }
    
    var summary: some View {
        VStack(alignment: .leading ,spacing: 24) {
            title
            assetDetail
            separator
            content
        }
        .padding(24)
        .background(Color.blue600)
        .cornerRadius(16)
    }
    
    var checkboxes: some View {
        VStack(spacing: 12) {
            Checkbox(isChecked: $isAmountCorrect, text: "referralOverviewCheckbox1")
            Checkbox(isChecked: $isAddressCorrect, text: "referralOverviewCheckbox2")
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("youreSending", comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.body16BrockmannMedium)
            .foregroundColor(.lightText)
    }
    
    var assetDetail: some View {
        HStack {
            Circle()
                .frame(width: 24, height: 24)
            
            Text("12")
                .foregroundColor(.neutral0)
            
            Text("RUNE")
                .foregroundColor(.lightText)
            
            Spacer()
        }
        .font(.body18BrockmannMedium)
    }
    
    var separator: some View {
        Separator()
    }
    
    var content: some View {
        VStack(spacing: 12) {
            getCell(
                title: "from",
                description: "Main Vault",
                bracketValue: "0xF42...9Ac5"
            )
            
            separator
            
            getCell(
                title: "to",
                description: "0xF43jf9840fkfjn38fk0dk9Ac5"
            )
            
            separator
            
            getCell(
                title: "network",
                description: "THORChain",
                icon: "0xF42...9Ac5"
            )
            
            separator
            
            getCell(
                title: "estNetworkFee",
                description: "1 RUNE"
            )
        }
    }
    
    var button: some View {
        FilledButton(title: "signTransaction")
    }
    
    private func getCell(title: String, description: String, bracketValue: String? = nil, icon: String? = nil) -> some View {
        HStack(spacing: 2) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(.extraLightGray)
            
            Spacer()
            
            if let icon {
                Circle()
                    .foregroundColor(.black)
                    .frame(width: 16, height: 16)
            }
            
            Text(description)
                .foregroundColor(.neutral0)
            
            if let bracketValue {
                Text("(\(title))")
                    .foregroundColor(.extraLightGray)
            }
        }
        .font(.body14BrockmannMedium)
    }
}

#Preview {
    ReferralSendOverviewView()
}
