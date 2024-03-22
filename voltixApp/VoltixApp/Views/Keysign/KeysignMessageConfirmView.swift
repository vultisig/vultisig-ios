//
//  KeysignMessageConfirmView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI

struct KeysignMessageConfirmView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            title
            summary
            button
        }
        .foregroundColor(.neutral0)
    }
    
    var title: some View {
        Text(NSLocalizedString("verify", comment: ""))
            .frame(maxWidth: .infinity, alignment: .center)
            .font(.body20MontserratSemiBold)
    }
    
    var summary: some View {
        ScrollView {
            VStack(spacing: 16) {
                toField
                Separator()
                amountField
            }
            .padding(16)
            .background(Color.blue600)
            .cornerRadius(10)
            .padding(16)
        }
    }
    
    var toField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("to", comment: "") + ":")
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            
            Text(viewModel.keysignPayload?.toAddress ?? "11")
                .font(.body12Menlo)
                .foregroundColor(.turquoise600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var amountField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("amount", comment: "") + ":")
                .font(.body20MontserratSemiBold)
                .foregroundColor(.neutral0)
            Text("\(viewModel.keysignPayload?.toAmount ?? 0)")
                .font(.body12Menlo)
                .foregroundColor(.turquoise600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var button: some View {
        Button(action: {
            self.viewModel.joinKeysignCommittee()
        }) {
            FilledButton(title: "joinKeySign")
        }
        .padding(20)
    }
}

#Preview {
    KeysignMessageConfirmView(viewModel: JoinKeysignViewModel())
}
