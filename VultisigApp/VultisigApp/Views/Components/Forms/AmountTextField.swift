//
//  AmountTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

enum PercentageFieldType {
    case button, slider
}

struct AmountTextField<CustomView: View>: View {
    enum CustomViewPosition {
        case balance
        case bottom
    }
    
    @Binding var amount: String
    @Binding var error: String?
    let ticker: String
    let type: PercentageFieldType
    let availableAmount: Decimal
    let decimals: Int
    @Binding var percentage: Double?
    let customView: CustomView
    let customViewPosition: CustomViewPosition
    @State var amountInternal: String = ""
    @State var size: CGSize?
    
    init(
        amount: Binding<String>,
        error: Binding<String?>,
        ticker: String,
        type: PercentageFieldType,
        availableAmount: Decimal,
        decimals: Int,
        percentage: Binding<Double?>,
        customViewPosition: CustomViewPosition = .balance,
        customView: () -> CustomView
    ) {
        self._amount = amount
        self._error = error
        self.ticker = ticker
        self.type = type
        self.availableAmount = availableAmount
        self.decimals = decimals
        self._percentage = percentage
        self.customViewPosition = customViewPosition
        self.customView = customView()
        self._amountInternal = State(initialValue: amount.wrappedValue)
    }
    
    init(
        amount: Binding<String>,
        error: Binding<String?>,
        ticker: String,
        type: PercentageFieldType,
        availableAmount: Decimal,
        decimals: Int,
        percentage: Binding<Double?>
    ) where CustomView == EmptyView {
        self.init(
            amount: amount,
            error: error,
            ticker: ticker,
            type: type,
            availableAmount: availableAmount,
            decimals: decimals,
            percentage: percentage,
            customViewPosition: .balance,
            customView: { EmptyView() }
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    TextField("0", text: $amountInternal)
                        .autocorrectionDisabled(true)
                        .multilineTextAlignment(.trailing)
                        .font(Theme.fonts.largeTitle)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .borderlessTextFieldStyle()
                        .fixedSize()
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    Text(ticker)
                        .font(Theme.fonts.largeTitle)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .fixedSize()
                }
                .frame(maxWidth: size?.width)
                
                if let percentage {
                    Text((Double(percentage) / 100).formatted(.percent))
                        .font(Theme.fonts.subtitle)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                if let error {
                    Text(error.localized)
                        .foregroundColor(Theme.colors.alertError)
                        .font(Theme.fonts.footnote)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                percentageView
                
                if customViewPosition == .balance {
                    unwrappedCustomView
                }
                
                availableBalanceView
                
                if customViewPosition == .bottom {
                    unwrappedCustomView
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
        .onChange(of: percentage) { _, _ in
            setupAmount()
        }
        .onLoad { setupAmount() }
        .onChange(of: availableAmount) { _, _ in
            setupAmount()
        }
        .readSize(onChange: { size = $0 })
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
                .foregroundStyle(Theme.colors.textSecondary)
        }
        .font(Theme.fonts.bodySMedium)
    }
    
    func setupAmount() {
        guard let percentage else { return }
        let multiplier = (Decimal(percentage) / 100)
        let amountDecimal = availableAmount * multiplier
        amount = amountDecimal.formatToDecimal(digits: decimals)
    }
    
    @ViewBuilder
    var unwrappedCustomView: some View {
        if !(customView is EmptyView) {
            customView
        }
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
