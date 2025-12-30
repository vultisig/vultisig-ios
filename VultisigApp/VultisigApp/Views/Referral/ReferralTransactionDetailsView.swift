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
    @EnvironmentObject var appViewModel: AppViewModel
    
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
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
                .padding(.top, 12)
            
            Text("\(referralViewModel.totalFeeFiat)")
                .font(Theme.fonts.caption10)
                .foregroundColor(Theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.bgSurface2, lineWidth: 1)
        )
    }
    
    var summary: some View {
        VStack(spacing: 12) {
            transactionHashLink
            
            separator
            
            getCell(
                title: "from",
                description: sendTx.vault?.name ?? "",
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
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.bgSurface2, lineWidth: 1)
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
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
        }
    }
    
    var headerTitle: some View {
        Text(NSLocalizedString("transactionDetails", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyLMedium)
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
                .foregroundColor(Theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            if let icon {
                Image(icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .cornerRadius(32)
            }
            
            Text(description)
                .foregroundColor(Theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            if let bracketValue {
                Text("(\(bracketValue))")
                    .foregroundColor(Theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(Theme.fonts.bodySMedium)
        .foregroundColor(Theme.colors.textPrimary)
    }
    
    var button: some View {
        PrimaryButton(title: "done") {
            appViewModel.restart()
        }
    }
}

#Preview {
    ReferralTransactionDetailsView(hash: "", sendTx: SendTransaction(), referralViewModel: ReferralViewModel())
        .environmentObject(AppViewModel())
}
