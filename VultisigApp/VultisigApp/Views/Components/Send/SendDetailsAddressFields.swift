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
    @FocusState.Binding var focusedField: Field?
    
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
                    .foregroundColor(Theme.colors.textPrimary)
            }
            
            Text(tx.fromAddress)
                .foregroundColor(Theme.colors.textExtraLight)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(Theme.fonts.caption12).padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.bgTertiary, lineWidth: 1)
        )
        .padding(1)
    }
    
    var toField: some View {
        VStack(spacing: 8) {
            getTitle(for: "sendTo")
            SendCryptoAddressTextField(tx: tx, sendCryptoViewModel: sendCryptoViewModel)
                .focused($focusedField, equals: .toAddress)
                .id(Field.toAddress)
                .onSubmit {
                    viewModel.onSelect(tab: .amount)
                }
        }
    }
    
    private func getTitle(for title: String) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textExtraLight)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
