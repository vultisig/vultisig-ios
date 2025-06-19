//
//  ReferralTransactionOverviewView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-28.
//

import SwiftUI
import RiveRuntime

struct ReferralTransactionOverviewView: View {
    let hash: String
    let sendTx: SendTransaction
    @ObservedObject var referralViewModel: ReferralViewModel
    
    @State var animationVM: RiveViewModel? = nil
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .onAppear {
            setData()
        }
    }
    
    var content: some View {
        VStack(spacing: 0) {
            animation
            payoutAsset
            transactionDetails
            Spacer()
            button
        }
        .padding(.horizontal, 24)
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
    
    var transactionDetails: some View {
        HStack {
            Text(NSLocalizedString("transactionDetails", comment: ""))
            Spacer()
            Image(systemName: "chevron.right")
        }
        .font(.body14BrockmannMedium)
        .foregroundColor(.lightText)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.blue600)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue400, lineWidth: 1)
        )
        .padding(.top, 8)
    }
    
    var button: some View {
        FilledButton(title: "done")
    }
    
    var animation: some View {
        ZStack {
            animationVM?.view()
                .frame(width: 280, height: 280)
            
            animationText
                .offset(y: 50)
        }
    }
    
    var animationText: some View {
        Text(NSLocalizedString("transactionSuccessful", comment: ""))
            .foregroundStyle(LinearGradient.primaryGradient)
            .font(.body18BrockmannMedium)
    }
    
    private func setData() {
        animationVM = RiveViewModel(fileName: "vaultCreatedAnimation", autoPlay: true)
    }
}

#Preview {
    ReferralTransactionOverviewView(hash: "", sendTx: SendTransaction(), referralViewModel: ReferralViewModel())
}
