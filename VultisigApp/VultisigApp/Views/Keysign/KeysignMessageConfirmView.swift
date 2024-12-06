//
//  KeysignMessageConfirmView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI

struct KeysignMessageConfirmView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel
    @StateObject var blowfishViewModel = BlowfishWarningViewModel()
    
    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 24) {
                title
                summary
                button
            }
            .foregroundColor(.neutral0)
            .onAppear {
                viewModel.blowfishTransactionScan()
                blowfishViewModel.updateResponse(viewModel.blowfishWarnings)
            }
            .task {
                await viewModel.loadThorchainID()
                await viewModel.loadFunctionName()
            }
        }
    }
    
    var blowfishView: some View {
        BlowfishWarningInformationNote(viewModel: blowfishViewModel)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
    }
    
    var title: some View {
        Text(NSLocalizedString("verify", comment: ""))
            .frame(maxWidth: .infinity, alignment: .center)
            .font(.body20MontserratSemiBold)
    }
    
    var summary: some View {
        ScrollView {
            VStack(spacing: 16) {
                fromField
                Separator()
                toField
                Separator()
                
                if let memo = viewModel.keysignPayload?.memo, !memo.isEmpty {
                    getSummaryCell(title: "memo", value: memo)
                    Separator()
                }
                
                if let decodedMemo = viewModel.decodedMemo {
                    functionField(decodedMemo: decodedMemo)
                    Separator()
                }
                
                amountField
                Separator()
                valueField

                Separator()
            }
            .padding(16)
            .background(Color.blue600)
            .cornerRadius(10)
            .padding(16)
            
            if viewModel.blowfishShow {
                blowfishView
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
