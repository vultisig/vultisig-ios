//
//  SendDetailsAddressFields.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-30.
//

import SwiftUI

struct SendDetailsAddressFields: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var viewModel: SendDetailsViewModel
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            fromField
            toField
        }
    }
    
    var fromField: some View {
        VStack(spacing: 12) {
            getTitle(for: "from")
            fromDetailsField
        }
        
    }
    
    var fromDetailsField: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let vaultName = homeViewModel.selectedVault?.name {
                Text(vaultName)
                    .foregroundColor(.neutral0)
            }
            
            Text(tx.fromAddress)
                .foregroundColor(.extraLightGray)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.body12BrockmannMedium).padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Color.blue600)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue400, lineWidth: 1)
        )
        .padding(1)
    }
    
    var toField: some View {
        VStack(spacing: 8) {
            getTitle(for: "sendTo")
            SendCryptoAddressTextField(tx: tx, sendCryptoViewModel: sendCryptoViewModel)
//                .focused($focusedField, equals: .toAddress)
//                .id(Field.toAddress)
//                .onSubmit {
//                    focusNextField($focusedField)
//                }
        }
    }
    
    private func getTitle(for title: String) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SendDetailsAddressFields(tx: SendTransaction(), viewModel: SendDetailsViewModel(), sendCryptoViewModel: SendCryptoViewModel())
}
