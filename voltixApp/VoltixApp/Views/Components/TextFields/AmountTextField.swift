//
//  AmountTextField.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct AmountTextField: View {
    @Binding var amount: String
    
    var body: some View {
        ZStack(alignment: .trailing) {
            if amount.isEmpty {
                Text(NSLocalizedString("enterAmount", comment: ""))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack(spacing: 0) {
                TextField(NSLocalizedString("enterAmount", comment: "").capitalized, text: $amount)
                    .submitLabel(.next)
                
                maxButton
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
        Text(NSLocalizedString("max", comment: "").uppercased())
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .frame(width: 40, height: 40)
    }
}

#Preview {
    AmountTextField(amount: .constant("0"))
}
