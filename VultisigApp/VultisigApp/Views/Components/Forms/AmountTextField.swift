//
//  AmountTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct AmountTextField: View {
    enum PercentageFieldType {
        case button, slider
    }
    
    @Binding var amount: String
    @Binding var error: String?
    let ticker: String
    let type: PercentageFieldType
    let availableAmount: Decimal
    let decimals: Int
    @Binding var percentage: Int?
    
    @State var amountInternal: String = ""
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        TextField("0", text: $amountInternal)
                            .autocorrectionDisabled(true)
                            .multilineTextAlignment(.trailing)
                            .font(Theme.fonts.largeTitle)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .keyboardType(.decimalPad)
                            .fixedSize()
                        Text(ticker)
                            .font(Theme.fonts.largeTitle)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .fixedSize()
                    }
                    .frame(maxWidth: geo.size.width)

                    if let percentage {
                        Text((Double(percentage) / 100).formatted(.percent))
                            .font(Theme.fonts.subtitle)
                            .foregroundStyle(Theme.colors.textExtraLight)
                    }
                }
                Spacer()
                VStack(spacing: 8) {
                    if let error {
                        Text(error.localized)
                            .foregroundColor(Theme.colors.alertError)
                            .font(Theme.fonts.footnote)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    percentageView
                    availableBalanceView
                }
            }
        }
        .onChange(of: amountInternal) { _, newValue in
            guard amount != newValue else { return }
            amount = newValue
            percentage = nil
        }
        .onChange(of: amount) { _, newValue in
            amountInternal = newValue
        }
        .onChange(of: percentage) { _, percentage in
            guard let percentage else { return }
            let multiplier = (Decimal(percentage) / 100)
            let amountDecimal = availableAmount * multiplier
            amount = amountDecimal.formatToDecimal(digits: decimals)
        }
    }
    
    @ViewBuilder
    var percentageView: some View {
        switch type {
        case .button:
            PercentageButtonsStack(selectedPercentage: $percentage)
        case .slider:
            PercentageSliderView(percentage: $percentage)
        }
    }
    
    var availableBalanceView: some View {
        HStack {
            Text("balanceAvailable".localized)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            Text("\(availableAmount.formatted(.number.precision(.fractionLength(4)))) \(ticker)")
                .foregroundStyle(Theme.colors.textLight)
        }
        .font(Theme.fonts.bodySMedium)
        .padding(.top, 4)
    }
}

#Preview {
    @Previewable @State var amount: String = "0"
    
    VStack {
        AmountTextField(
            amount: $amount,
            error: .constant(nil),
            ticker: "RUNE",
            type: .button,
            availableAmount: 100,
            decimals: 6,
            percentage: .constant(nil)
        )
        
        AmountTextField(
            amount: $amount,
            error: .constant(nil),
            ticker: "RUNE",
            type: .slider,
            availableAmount: 100,
            decimals: 6,
            percentage: .constant(nil)
        )
    }
    .padding()
    .background(Theme.colors.bgPrimary)
}
