//
//  SendDetailsAmountTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-02.
//

import SwiftUI

struct SendDetailsAmountTab: View {
    let isExpanded: Bool
    @ObservedObject var tx: SendTransaction
    @ObservedObject var viewModel: SendDetailsViewModel
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    let validateForm: () async -> ()
    @FocusState.Binding var focusedField: Field?
    @Binding var settingsPresented: Bool
    
    var body: some View {
        content
            .padding(.bottom, 100)
            .clipped()
            .onChange(of: isExpanded) { oldValue, newValue in
                Task {
                    setData(oldValue, newValue)
                }
            }
    }
    
    var content: some View {
        SendFormExpandableSection(isExpanded: isExpanded) {
            titleSection
        } content: {
            separator
            amountFieldSection
            
            if sendCryptoViewModel.showAmountAlert {
                errorText
            }
            
            percentageButtons
            balanceSection
            additionalOptionsSection
        }
    }
    
    var titleSection: some View {
        HStack {
            Text(NSLocalizedString("amount", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
            
            Spacer()
            
            if showGasSelector {
                gasSelector
            }
        }
        .background(Background().opacity(0.01))
        .onTapGesture {
            viewModel.onSelect(tab: .amount)
        }
    }
    
    var separator: some View {
        LinearSeparator()
    }
    
    var showGasSelector: Bool {
        isExpanded && tx.coin.supportsFeeSettings
    }
    
    var gasSelector: some View {
        Button {
            settingsPresented.toggle()
        } label: {
            editLabel
        }
    }
    
    var editLabel: some View {
        Image(systemName: "fuelpump")
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyMMedium)
    }
    
    var amountFieldSection: some View {
        SendDetailsAmountTextField(tx: tx, viewModel: viewModel, sendCryptoViewModel: sendCryptoViewModel)
            .focused($focusedField, equals: .amount)
            .id(Field.amount)
            .onSubmit {
                Task{
                    await validateForm()
                }
            }
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
        .font(Theme.fonts.bodySMedium)
        .foregroundColor(Theme.colors.textPrimary)
        .padding(12)
        .padding(.vertical, 8)
        .background(Color.blue600)
        .cornerRadius(12)
    }
    
    var additionalOptionsSection: some View {
        SendDetailsAdditionalSection(tx: tx, viewModel: viewModel, sendCryptoViewModel: sendCryptoViewModel)
    }
    
    var errorText: some View {
        Text(NSLocalizedString(sendCryptoViewModel.errorMessage, comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundColor(.alertYellow)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func getPercentageButtons(for value: String) -> some View {
        Text(value)
            .foregroundColor(Theme.colors.textPrimary)
            .padding(4)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 32)
                    .stroke(Color.blue400, lineWidth: 1)
            )
    }
    
    private func setData(_ oldValue: Bool, _ newValue: Bool) {
        guard oldValue != newValue, !newValue else {
            focusedField = .amount
            return
        }
    }
}
