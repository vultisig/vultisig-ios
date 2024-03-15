//
//  AddressTextField.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

struct AddressTextField: View {
    @Binding var address: String
    
    var body: some View {
        ZStack(alignment: .trailing) {
            if address.isEmpty {
                Text(NSLocalizedString("enterAddress", comment: ""))
                    .foregroundColor(Color.neutral0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack(spacing: 0) {
                TextField(NSLocalizedString("enterAddress", comment: "").capitalized, text: $address)
                    .foregroundColor(.neutral0)
                    .submitLabel(.next)
                
                scanButton
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
    
    var scanButton: some View {
        Image(systemName: "camera")
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .frame(width: 40, height: 40)
    }
}

#Preview {
    AddressTextField(address: .constant(""))
}
