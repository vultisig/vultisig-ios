//
//  ReferralTransactionDetailsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-30.
//

import SwiftUI

struct ReferralTransactionDetailsView: View {
    let hash: String
    let sendTx: SendTransaction
    @ObservedObject var referralViewModel: ReferralViewModel
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
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
            Image("rune")
                .resizable()
                .frame(width: 36, height: 36)
                .cornerRadius(32)
            
            Text("\(sendTx.amount) RUNE")
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
                .padding(.top, 12)
            
            Text("\(referralViewModel.totalFeeFiat)")
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
                description: hash
            )
            
            separator
            
            getCell(
                title: "from",
                description: homeViewModel.selectedVault?.name ?? "",
                bracketValue: referralViewModel.nativeCoin?.address
            )
            
            separator
            
            getCell(
                title: "network",
                description: "THORChain",
                icon: "rune"
            )
            
            separator
            
            getCell(
                title: "estNetworkFee",
                description: sendTx.gasInReadable
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
                Image(icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .cornerRadius(32)
            }
            
            Text(description)
                .foregroundColor(.neutral0)
            
            if let bracketValue {
                Text("(\(bracketValue))")
                    .foregroundColor(.extraLightGray)
            }
        }
        .font(.body14BrockmannMedium)
    }
    
    var button: some View {
        NavigationLink {
            HomeView()
        } label: {
            label
        }
    }
    
    var label: some View {
        FilledButton(title: "done")
    }
}

#Preview {
    ReferralTransactionDetailsView(hash: "", sendTx: SendTransaction(), referralViewModel: ReferralViewModel())
}
