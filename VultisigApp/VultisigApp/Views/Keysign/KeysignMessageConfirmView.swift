//
//  KeysignMessageConfirmView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI

struct KeysignMessageConfirmView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel
    
    @State var warnings: [BlowfishResponse.BlowfishWarning] = []
    @State var isLoading = true
    
    var body: some View {
        ZStack {
            
            if isLoading {
                Loader()
            }
            
            VStack(alignment: .leading, spacing: 24) {
                title
                summary
                
                HStack {
                    Spacer()
                    if (viewModel.keysignPayload?.coin.chainType == .EVM) {
                        warning
                    }
                    Spacer()
                }
                
                button
            }
            .foregroundColor(.neutral0)
            .onAppear {
                if (viewModel.keysignPayload?.coin.chainType == .EVM) {
                    isLoading = true
                    Task{
                        do {
                            let scannerResult = try await viewModel.blowfishEVMTransactionScan()
                            warnings = scannerResult?.warnings ?? [];
                            isLoading = false
                        } catch {
                            print(error.localizedDescription)
                            isLoading = false
                        }
                    }
                } else {
                    isLoading = false
                }
            }
        }
    }
    
    var warning: some View {
        VStack {
            BlowfishWarningInformationNote(blowfishMessages: warnings)
                .padding(.horizontal, 16)
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
                fromField
                Separator()
                toField
                Separator()
                amountField
                
                if let memo = viewModel.keysignPayload?.memo, !memo.isEmpty {
                    Separator()
                    getSummaryCell(title: "memo", value: memo)
                }
                
                Separator()
                
                //gasField
            }
            .padding(16)
            .background(Color.blue600)
            .cornerRadius(10)
            .padding(16)
        }
    }
    
    var fromField: some View {
        getPrimaryCell(title: "from", value: viewModel.keysignPayload?.coin.address ?? "")
    }
    
    var toField: some View {
        getPrimaryCell(title: "to", value: viewModel.keysignPayload?.toAddress ?? "")
    }
    
    var amountField: some View {
        getSummaryCell(title: "amount", value: viewModel.keysignPayload?.toAmountString ?? "")
    }
    
    var gasField: some View {
        getSummaryCell(title: "gas", value: "$4.00")
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
                .font(.body12Menlo)
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
    KeysignMessageConfirmView(viewModel: JoinKeysignViewModel())
}
