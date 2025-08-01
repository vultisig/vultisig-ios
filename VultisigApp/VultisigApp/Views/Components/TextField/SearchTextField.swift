//
//  SearchTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

struct SearchTextField: View {
    @Binding var value: String
    
    var showClearButton: Bool {
        value.isNotEmpty
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.extraLightGray)
            
            TextField(NSLocalizedString("Search", comment: "Search"), text: $value)
                .font(.body16BrockmannMedium)
                .foregroundColor(.extraLightGray)
                .disableAutocorrection(true)
                .borderlessTextFieldStyle()
                .colorScheme(.dark)
                .padding(.horizontal, 8)
            
            clearButton
                .opacity(showClearButton ? 1 : 0)
                .animation(.easeInOut, value: showClearButton)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(12)
    }
    
    var clearButton: some View {
        Button {
            value = .empty
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.neutral500)
        }
    }
}
