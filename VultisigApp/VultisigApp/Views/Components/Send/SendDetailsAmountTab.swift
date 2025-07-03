//
//  SendDetailsAmountTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-02.
//

import SwiftUI

struct SendDetailsAmountTab: View {
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
                amountFieldSection
                percentageButtons
                balanceSection
                additionalOptionsSection
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
            Text(NSLocalizedString("amount", comment: ""))
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
            
            Spacer()
            gasSelector
        }
    }
    
    var separator: some View {
        LinearSeparator()
    }
    
    var gasSelector: some View {
        Button {
            
        } label: {
            editLabel
        }
    }
    
    var editLabel: some View {
        Image(systemName: "fuelpump")
            .foregroundColor(.neutral0)
            .font(.body16BrockmannMedium)
    }
    
    var amountFieldSection: some View {
        SendDetailsAmountTextField(tx: tx, viewModel: viewModel, sendCryptoViewModel: sendCryptoViewModel)
    }
    
    var percentageButtons: some View {
        HStack(spacing: 12) {
            Button {
                sendCryptoViewModel.setMaxValues(tx: tx, percentage: 25)
            } label: {
                getPercentageButtons(for: "25%")
            }
            
            Button {
                sendCryptoViewModel.setMaxValues(tx: tx, percentage: 50)
            } label: {
                getPercentageButtons(for: "50%")
            }
            
            Button {
                sendCryptoViewModel.setMaxValues(tx: tx, percentage: 75)
            } label: {
                getPercentageButtons(for: "75%")
            }
            
            Button {
                sendCryptoViewModel.setMaxValues(tx: tx)
            } label: {
                getPercentageButtons(for: "Max")
            }
        }
    }
    
    var balanceSection: some View {
        HStack {
            Text(NSLocalizedString("balanceAvailable", comment: ""))
            Spacer()
            Text(tx.coin.balanceString + " " + tx.coin.ticker)
        }
        .font(.body14BrockmannMedium)
        .foregroundColor(.neutral0)
        .padding(12)
        .padding(.vertical, 8)
        .background(Color.blue600)
        .cornerRadius(12)
    }
    
    var additionalOptionsSection: some View {
        SendDetailsAdditionalSection(tx: tx, viewModel: viewModel, sendCryptoViewModel: sendCryptoViewModel)
    }
    
    private func getPercentageButtons(for value: String) -> some View {
        Text(value)
            .foregroundColor(.neutral0)
            .padding(4)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 32)
                    .stroke(Color.blue400, lineWidth: 1)
            )
    }
}

#Preview {
    SendDetailsAmountTab(tx: SendTransaction(), viewModel: SendDetailsViewModel(), sendCryptoViewModel: SendCryptoViewModel())
}
