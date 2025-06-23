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
    
    @Environment(\.openURL) var openURL
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .navigationBarBackButtonHidden(true)
    }
    
    var content: some View {
        VStack(spacing: 16) {
            headerTitle
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
            transactionHashLink
            
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
    
    var transactionHashLink: some View {
        Button {
            openLink()
        } label: {
            transactionHashLabel
        }
    }
    
    var transactionHashLabel: some View {
        HStack {
            getCell(
                title: "transactionHash",
                description: hash
            )
            
            Image(systemName: "arrow.up.forward.app")
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
        }
    }
    
    var headerTitle: some View {
        Text(NSLocalizedString("transactionDetails", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body18BrockmannMedium)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }
    
    func openLink() {
        let urlString = "https://thorchain.net/tx/\(hash)"
        
        if let url = URL(string: urlString) {
            openURL(url)
        }
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
        .foregroundColor(.neutral0)
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
