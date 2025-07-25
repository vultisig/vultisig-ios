//
//  KeysignMessageConfirmView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI

struct KeysignMessageConfirmView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel
    
    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                let fees = viewModel.getCalculatedNetworkFee()
                SendCryptoVerifySummaryView(
                    input: SendCryptoVerifySummary(
                        fromName: viewModel.vault.name,
                        fromAddress: viewModel.keysignPayload?.coin.address ?? .empty,
                        toAddress: viewModel.keysignPayload?.toAddress ?? .empty,
                        network: viewModel.keysignPayload?.coin.chain.name ?? .empty,
                        networkImage: viewModel.keysignPayload?.coin.chain.logo ?? .empty,
                        memo: viewModel.memo ?? .empty,
                        feeCrypto: fees.feeCrypto,
                        feeFiat: fees.feeFiat,
                        coinImage: viewModel.keysignPayload?.coin.logo ?? .empty,
                        amount: viewModel.keysignPayload?.toAmountString ?? .empty,
                        coinTicker: viewModel.keysignPayload?.coin.ticker ?? .empty
                    )
                ) {
                    SecurityScanView(viewModel: viewModel.securityScanViewModel)
                        .padding(.horizontal, 16)
                        .showIf(viewModel.showSecurityScan)
                }
                
                PrimaryButton(title: "joinTransactionSigning") {
                    viewModel.joinKeysignCommittee()
                }
            }
            .task {
                await viewModel.loadThorchainID()
                await viewModel.loadFunctionName()
                await viewModel.performSecurityScan()
            }
        }
        .navigationTitle("sendOverview")
    }
    
    var title: some View {
        Text(NSLocalizedString("verify", comment: ""))
            .frame(maxWidth: .infinity, alignment: .center)
            .font(.body20MontserratSemiBold)
    }
}

#Preview {
    ZStack {
        Background()
        KeysignMessageConfirmView(viewModel: JoinKeysignViewModel())
    }
}
