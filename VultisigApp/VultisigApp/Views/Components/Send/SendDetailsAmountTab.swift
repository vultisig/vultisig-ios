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
            .onChange(of: isExpanded) { _, newValue in
                guard newValue else {
                    return
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = .amount
                }
            }
    }
    
    var content: some View {
        SendFormExpandableSection(isExpanded: isExpanded) {
            titleSection
        } content: {
            VStack(spacing: 16) {
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
        SendDetailsAmountTextField(tx: tx, viewModel: viewModel, sendCryptoViewModel: sendCryptoViewModel, focusedField: $focusedField)
            .id(Field.amount)
            .onSubmit {
                Task{
                    await validateForm()
                }
            }
    }
    
    var percentageButtons: some View {
        let isDisabled = sendCryptoViewModel.isLoading || tx.isCalculatingFee
        
        return HStack(spacing: 12) {
            Button {
                sendCryptoViewModel.setMaxValues(tx: tx, percentage: 25)
            } label: {
                getPercentageButtons(for: "25%")
            }
            .disabled(isDisabled)
            
            Button {
                sendCryptoViewModel.setMaxValues(tx: tx, percentage: 50)
            } label: {
                getPercentageButtons(for: "50%")
            }
            .disabled(isDisabled)
            
            Button {
                sendCryptoViewModel.setMaxValues(tx: tx, percentage: 75)
            } label: {
                getPercentageButtons(for: "75%")
            }
            .disabled(isDisabled)
            
            Button {
                sendCryptoViewModel.setMaxValues(tx: tx)
            } label: {
                getPercentageButtons(for: "Max")
            }
            .disabled(isDisabled)
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
        .background(Theme.colors.bgSecondary)
        .cornerRadius(12)
    }
    
    var additionalOptionsSection: some View {
        SendDetailsAdditionalSection(tx: tx, viewModel: viewModel, sendCryptoViewModel: sendCryptoViewModel)
    }
    
    var errorText: some View {
        Text(NSLocalizedString(sendCryptoViewModel.errorMessage ?? .empty, comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.alertWarning)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func getPercentageButtons(for value: String) -> some View {
        let isDisabled = sendCryptoViewModel.isLoading || tx.isCalculatingFee
        
        return Text(value)
            .foregroundColor(isDisabled ? Theme.colors.textExtraLight : Theme.colors.textPrimary)
            .padding(4)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 32)
                    .stroke(isDisabled ? Theme.colors.bgTertiary.opacity(0.5) : Theme.colors.bgTertiary, lineWidth: 1)
            )
            .opacity(isDisabled ? 0.5 : 1.0)
    }
}
