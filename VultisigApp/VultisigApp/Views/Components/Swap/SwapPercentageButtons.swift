//
//  SwapPercentageButtons.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-25.
//

import SwiftUI

struct SwapPercentageButtons: View {
    let buttonOptions = [25, 50, 75, 100]
    
    let onTap: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            buttons
            separator
        }
        .frame(maxWidth: .infinity)
    }
    
    var separator: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundColor(.blue400)
    }
    
    var buttons: some View {
        HStack(spacing: 8) {
            ForEach(buttonOptions, id: \.self) { option in
                getPercentageButton(for: option)
            }
        }
    }
    
    private func getPercentageButton(for option: Int) -> some View {
        Button(action: {
            onTap(option)
        }) {
            getPercentageCell(for: "\(option)")
        }
    }
    
    private func getPercentageCell(for text: String) -> some View {
        Text(text + "%")
            .font(.body12BrockmannMedium)
            .foregroundColor(.neutral0)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.blue600)
            .cornerRadius(32)
    }
}
