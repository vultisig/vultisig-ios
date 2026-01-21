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
    let validateForm: () async -> Void
    @FocusState.Binding var focusedField: Field?
    @Binding var settingsPresented: Bool
    @State var percentage: Double?
    
    var body: some View {
        content
            .padding(.bottom, 65)
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
                Task {
                    await validateForm()
                }
            }
    }
    
    @ViewBuilder
    var percentageButtons: some View {
        let isDisabled = sendCryptoViewModel.isLoading || tx.isCalculatingFee
        PercentageButtonsStack(selectedPercentage: $percentage)
        .opacity(isDisabled ? 0.5 : 1.0)
        .disabled(isDisabled)
        .onChange(of: percentage) { _, newValue in
            guard let newValue else { return }
            sendCryptoViewModel.setMaxValues(tx: tx, percentage: newValue)
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
        .background(Theme.colors.bgSurface1)
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
}
