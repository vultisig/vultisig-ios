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
    let ticker: String
    let type: PercentageFieldType
    var onPercentage: (Int) -> Void
    
    @State var percentage: Int?
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer()
                ZStack(alignment: .bottom) {
                    HStack(spacing: 4) {
                        TextField("0", text: $amount)
                            .autocorrectionDisabled(true)
                            .multilineTextAlignment(.trailing)
                            .font(Theme.fonts.largeTitle)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .keyboardType(.decimalPad)
                            .fixedSize()
                        
                        Text(ticker)
                            .font(Theme.fonts.largeTitle)
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                    .frame(maxWidth: geo.size.width)

                    if let percentage {
                        Text("\(percentage)%")
                            .font(Theme.fonts.subtitle)
                            .foregroundStyle(Theme.colors.textExtraLight)
                            .offset(y: 16)
                    }
                }
                Spacer()
                percentageView
            }
        }
    }
    
    @ViewBuilder
    var percentageView: some View {
        switch type {
        case .button:
            PercentageButtonsStack {
                onPercentage($0)
            }
        case .slider:
            PercentageSliderView {
                percentage = $0
                onPercentage($0)
            }
        }
    }
}

#Preview {
    @Previewable @State var amount: String = "0"
    
    VStack {
        AmountTextField(
            amount: $amount,
            ticker: "RUNE",
            type: .button
        ) { _ in }
        
        AmountTextField(
            amount: $amount,
            ticker: "RUNE",
            type: .slider
        ) { _ in }
    }
    .padding()
    .background(Theme.colors.bgPrimary)
}
