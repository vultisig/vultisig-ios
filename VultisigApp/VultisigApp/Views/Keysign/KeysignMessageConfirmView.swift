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
            VStack(alignment: .leading, spacing: 24) {
                title
                summary
                button
            }
            .foregroundColor(.neutral0)
            .task {
                await viewModel.loadThorchainID()
                await viewModel.loadFunctionName()
                await viewModel.performSecurityScan()
            }
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("verify", comment: ""))
            .frame(maxWidth: .infinity, alignment: .center)
            .font(.body20MontserratSemiBold)
    }
    
    var summary: some View {
        ScrollView {
            VStack(spacing: 16) {
                
                if let from = viewModel.keysignPayload?.coin.address, !from.isEmpty {
                    fromField
                    Separator()
                }

                if let to = viewModel.keysignPayload?.toAddress, !to.isEmpty {
                    toField
                    Separator()
                }
                
                if let memo = viewModel.keysignPayload?.memo, !memo.isEmpty {
                    // Show decoded memo if available, otherwise show raw memo as fallback
                    if let decodedMemo = viewModel.decodedMemo, !decodedMemo.isEmpty {
                        functionField(decodedMemo: decodedMemo)
                        Separator()
                    } else {
                        // Only show raw memo if decoding completely failed
                        getSummaryCell(title: "memo", value: memo)
                        Separator()
                    }
                }
                
                if let amount = viewModel.keysignPayload?.toAmountString, !amount.isEmpty {
                    amountField
                    Separator()
                }

                if let fiat = viewModel.keysignPayload?.toAmountFiatString, !fiat.isEmpty {
                    valueField
                    Separator()
                }
                
                networkFeeField
            }
            .padding(16)
            .background(Color.blue600)
            .cornerRadius(10)
            .padding(16)
            
            if viewModel.showSecurityScan {
                SecurityScanView(viewModel: viewModel.securityScanViewModel)
                    .padding(.horizontal, 16)
            }
        }
    }
    
    var fromField: some View {
        getPrimaryCell(title: "from", value: viewModel.keysignPayload?.coin.address ?? "")
    }
    
    var toField: some View {
        getPrimaryCell(title: "to", value: viewModel.keysignPayload?.toAddress ?? "")
    }
    
    var valueField: some View {
        getSummaryCell(title: "value", value: viewModel.keysignPayload?.toAmountFiatString ?? "")
    }
    
    var networkFeeField: some View {
        getSummaryCell(title: "networkFee", value: viewModel.getCalculatedNetworkFee())
    }
    
    var amountField: some View {
        getSummaryCell(title: "amount", value: viewModel.keysignPayload?.toAmountString ?? "")
    }
    
    func functionField(decodedMemo: String) -> some View {
        getSummaryCell(title: "function", value: decodedMemo)
    }
    
    var button: some View {
        Button(action: {
            self.viewModel.joinKeysignCommittee()
        }) {
            FilledButton(title: "joinKeySign")
        }
        .padding(20)
    }
    
    private func getPrimaryCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString(title, comment: "") + ":")
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            Text(value)
                .font(.body13MenloBold)
                .foregroundColor(.turquoise600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func getSummaryCell(title: String, value: String) -> some View {
        HStack {
            Text(NSLocalizedString(title, comment: "") + ":")
            Spacer()
            Text(value)
        }
        .font(.body16MenloBold)
        .foregroundColor(.neutral0)
    }
}

#Preview {
    ZStack {
        Background()
        KeysignMessageConfirmView(viewModel: JoinKeysignViewModel())
    }
}
