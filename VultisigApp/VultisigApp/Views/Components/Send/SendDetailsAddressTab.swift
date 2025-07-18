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
            .onChange(of: tx.toAddress) { oldValue, newValue in
                Task {
                    guard await sendCryptoViewModel.validateToAddress(tx: tx) else {
                        viewModel.selectedTab = .Address
                        return
                    }
                    viewModel.selectedTab = .Amount
                }
            }
    }
    
    var content: some View {
        VStack(spacing: 16) {
            titleSection
            
            if isExpanded {
                separator
                fields
            }
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue200, lineWidth: 1)
        )
        .padding(1)
    }
    
    var titleSection: some View {
        HStack {
            Text(NSLocalizedString("address", comment: ""))
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
            
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
            viewModel.selectedTab = .Address
        }
    }
    
    var separator: some View {
        LinearSeparator()
    }
    
    var selectedAddress: some View {
        Text("\(tx.toAddress)")
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
            .lineLimit(1)
            .truncationMode(.middle)
    }
    
    var doneEditTools: some View {
        SendDetailsTabEditTools(forTab: .Address, viewModel: viewModel)
    }
    
    var fields: some View {
        SendDetailsAddressFields(tx: tx, viewModel: viewModel, sendCryptoViewModel: sendCryptoViewModel, focusedField: $focusedField)
    }
    
    private func handleClose(_ oldValue: Bool, _ newValue: Bool) async {
        guard oldValue != newValue, !newValue else {
            focusedField = .toAddress
            return
        }
        if !tx.toAddress.isEmpty {
            guard await sendCryptoViewModel.validateToAddress(tx: tx) else {
                viewModel.selectedTab = .Address
                return
            }
        }
        
        viewModel.addressSetupDone = true
    }
}
