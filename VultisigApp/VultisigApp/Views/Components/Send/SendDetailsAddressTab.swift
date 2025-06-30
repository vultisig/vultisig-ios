//
//  SendDetailsAddressTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-30.
//

import SwiftUI

struct SendDetailsAddressTab: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var viewModel: SendDetailsViewModel
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    
    @State var isExpanded: Bool = true
    
    var body: some View {
        content
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
    }
    
    var separator: some View {
        LinearSeparator()
    }
    
    var selectedAddress: some View {
        Text("\(tx.toAddress)")
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
    }
    
    var doneEditTools: some View {
        SendDetailsTabEditTools(forTab: .Address, viewModel: viewModel)
    }
    
    var fields: some View {
        SendDetailsAddressFields(tx: tx, viewModel: viewModel, sendCryptoViewModel: sendCryptoViewModel)
    }
}

#Preview {
    SendDetailsAddressTab(tx: SendTransaction(), viewModel: SendDetailsViewModel(), sendCryptoViewModel: SendCryptoViewModel())
}
