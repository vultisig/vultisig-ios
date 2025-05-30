//
//  ReferralTransactionDetailsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-30.
//

import SwiftUI

struct ReferralTransactionDetailsView: View {
    var body: some View {
        ZStack {
            Background()
            content
        }
    }
    
    var content: some View {
        VStack(spacing: 16) {
            payoutAsset
            summary
            Spacer()
            button
        }
        .padding(24)
    }
    
    var payoutAsset: some View {
        VStack(spacing: 2) {
            Circle()
                .foregroundColor(.black)
                .frame(width: 36, height: 36)
            
            Text("12 RUNE")
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
                .padding(.top, 12)
            
            Text("$12345")
                .font(.body10BrockmannMedium)
                .foregroundColor(.extraLightGray)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue400, lineWidth: 1)
        )
    }
    
    var summary: some View {
        VStack(spacing: 12) {
            getCell(
                title: "transactionHash",
                description: "0xF42...9Ac5"
            )
            
            separator
            
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
        .padding(24)
        .background(Color.blue600)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue400, lineWidth: 1)
        )
    }
    
    var separator: some View {
        Separator()
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
    
    var button: some View {
        FilledButton(title: "done")
    }
}

#Preview {
    ReferralTransactionDetailsView()
}
