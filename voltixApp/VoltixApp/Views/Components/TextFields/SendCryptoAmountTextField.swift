//
//  SendCryptoAmountTextField.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct SendCryptoAmountTextField: View {

    @Binding var amount: String

    var onChange: (String) async -> Void
    var onMaxPressed: () -> Void
    var showButton = true

	var body: some View {
		ZStack(alignment: .trailing) {
			if amount.isEmpty {
				Text(NSLocalizedString("enterAmount", comment: ""))
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			
			HStack(spacing: 0) {
				TextField(NSLocalizedString("enterAmount", comment: "").capitalized, text: Binding<String>(
					get: { amount },
					set: { newValue in
                        let newAmount = newValue.formatCurrency()
                        amount = newAmount
                        DebounceHelper.shared.debounce {
                            Task {
                                await onChange(newAmount)
                            }
                        }
					}
				))
				.submitLabel(.next)
				.textInputAutocapitalization(.never)
				.keyboardType(.decimalPad)
				.textContentType(.oneTimeCode)
				.disableAutocorrection(true)
				
				if showButton {
					maxButton
				}
			}
		}
		.font(.body12Menlo)
		.foregroundColor(.neutral0)
		.frame(height: 48)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 12)
		.background(Color.blue600)
		.cornerRadius(10)
	}
	
	var maxButton: some View {
		Button { onMaxPressed() } label: {
			Text(NSLocalizedString("max", comment: "").uppercased())
				.font(.body16Menlo)
				.foregroundColor(.neutral0)
				.frame(width: 40, height: 40)
		}
	}
}

#Preview {
    SendCryptoAmountTextField(
        amount: .constant(.empty), 
        onChange: { _ in },
        onMaxPressed: { }
    )
}
