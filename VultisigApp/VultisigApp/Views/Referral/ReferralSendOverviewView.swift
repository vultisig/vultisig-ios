//
//  ReferralSendOverviewView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-28.
//

import SwiftUI

struct ReferralSendOverviewView: View {
    @ObservedObject var sendTx: SendTransaction
    @ObservedObject var functionCallViewModel: FunctionCallViewModel
    @ObservedObject var functionCallVerifyViewModel: FunctionCallVerifyViewModel
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        ZStack {
            Background()
            container
        }
    }
    
    var content: some View {
        VStack(spacing: 16) {
            summary
            checkboxes
        }
        .padding(24)
    }
    
    var summary: some View {
        VStack(alignment: .leading ,spacing: 24) {
            title
            assetDetail
            overview
        }
        .padding(24)
        .background(Color.blue600)
        .cornerRadius(16)
    }
    
    var checkboxes: some View {
        VStack(spacing: 12) {
            Checkbox(isChecked: $functionCallVerifyViewModel.isReferralAmountCorrect, text: "referralOverviewCheckbox1")
            Checkbox(isChecked: $functionCallVerifyViewModel.isReferralAddressCorrect, text: "referralOverviewCheckbox2")
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
            Image("rune")
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(32)
            
            Text("\(sendTx.amount)")
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
    
    var overview: some View {
        VStack(spacing: 12) {
            separator
            
            getCell(
                title: "from",
                description: homeViewModel.selectedVault?.name ?? "",
                bracketValue: getVaultAddress()
            )
            
            separator
            
            getCell(
                title: "network",
                description: "THORChain",
                icon: "rune"
            )
            
            separator
            
            getCell(
                title: "gas",
                description: "\(sendTx.gasInReadable)"
            )
        }
    }
    
    private func getCell(title: String, description: String, bracketValue: String? = nil, icon: String? = nil) -> some View {
        HStack(spacing: 2) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundColor(.extraLightGray)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            if let icon {
                Image(icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .cornerRadius(16)
            }
            
            Text(description)
                .foregroundColor(.neutral0)
                .lineLimit(1)
                .truncationMode(.tail)
            
            if let bracketValue {
                Text("(\(bracketValue))")
                    .foregroundColor(.extraLightGray)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.body14BrockmannMedium)
    }
    
    private func getVaultAddress() -> String? {
        guard let nativeCoin = ApplicationState.shared.currentVault?.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) else {
            return nil
        }
        
        return nativeCoin.address
    }
}

#Preview {
    ReferralSendOverviewView(sendTx: SendTransaction(), functionCallViewModel: FunctionCallViewModel(), functionCallVerifyViewModel: FunctionCallVerifyViewModel())
        .environmentObject(HomeViewModel())
}
