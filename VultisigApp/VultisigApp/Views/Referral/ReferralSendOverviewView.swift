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
            
            VStack {
                header
                content
            }
            .navigationBarBackButtonHidden(true)
        }
    }
    
    var header: some View {
        HStack {
            backButton
            Spacer()
            headerTitle
            Spacer()
            backButton
                .opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    var backButton: some View {
        Button {
            functionCallViewModel.currentIndex -= 1
        } label: {
            NavigationBlankBackButton()
        }
    }
    
    var headerTitle: some View {
        Text(NSLocalizedString("sendOverview", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyLMedium)
    }
    
    var content: some View {
        VStack(spacing: 16) {
            Spacer()
            summary
            Spacer()
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
        .background(Theme.colors.bgSecondary)
        .cornerRadius(16)
    }
    
    var title: some View {
        Text(NSLocalizedString("youreSending", comment: ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(.lightText)
    }
    
    var assetDetail: some View {
        HStack {
            Image("rune")
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(32)
            
            Text("\(sendTx.amount)")
                .foregroundColor(Theme.colors.textPrimary)
            
            Text("RUNE")
                .foregroundColor(.lightText)
            
            Spacer()
        }
        .font(Theme.fonts.bodyLMedium)
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
            
            separator
            
            getCell(
                title: "memo",
                description: sendTx.memo,
                isForMemo: true
            )
        }
    }
    
    private func getCell(title: String, description: String, bracketValue: String? = nil, icon: String? = nil, isForMemo: Bool = false) -> some View {
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
                .foregroundColor(isForMemo ? .extraLightGray : Theme.colors.textPrimary)
                .lineLimit(isForMemo ? 2 : 1)
                .truncationMode(.tail)
            
            if let bracketValue {
                Text("(\(bracketValue))")
                    .foregroundColor(.extraLightGray)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(Theme.fonts.bodySMedium)
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
