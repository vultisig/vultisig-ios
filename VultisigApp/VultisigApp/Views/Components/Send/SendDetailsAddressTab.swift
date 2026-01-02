//
//  SendDetailsAddressTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-30.
//

import SwiftUI

struct SendDetailsAddressTab: View {
    let isExpanded: Bool
    @ObservedObject var tx: SendTransaction
    @ObservedObject var viewModel: SendDetailsViewModel
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    @FocusState.Binding var focusedField: Field?
    
    var body: some View {
        content
            .onChange(of: isExpanded) { oldValue, newValue in
                Task {
                    await handleClose(oldValue, newValue)
                }
            }
    }
    
    var content: some View {
        SendFormExpandableSection(isExpanded: isExpanded) {
            titleSection
        } content: {
            VStack(spacing: 16) {
                separator
                fields
            }
        }
    }
    
    var titleSection: some View {
        HStack {
            Text(NSLocalizedString("address", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
            
            if viewModel.addressSetupDone {
                selectedAddress
                Spacer()
                doneEditTools
            } else {
                Spacer()
            }
        }
        .background(Background().opacity(0.01))
        .onTapGesture {
            viewModel.onSelect(tab: .address)
        }
    }
    
    var separator: some View {
        LinearSeparator()
    }
    
    var selectedAddress: some View {
        Text("\(tx.toAddress)")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
    
    var doneEditTools: some View {
        SendDetailsTabEditTools(forTab: .address, viewModel: viewModel)
    }
    
    var fields: some View {
        SendDetailsAddressFields(tx: tx, viewModel: viewModel, sendCryptoViewModel: sendCryptoViewModel, focusedField: $focusedField)
    }
    
    private func handleClose(_ oldValue: Bool, _ newValue: Bool) async {
        guard oldValue != newValue, !newValue else {
            return
        }
        if !tx.toAddress.isEmpty {
            guard await sendCryptoViewModel.validateToAddress(tx: tx) else {
                viewModel.onSelect(tab: .address)
                return
            }
            viewModel.addressSetupDone = true
        }
    }
}
