//
//  SwapPercentageButtons.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-25.
//

import SwiftUI

struct SwapPercentageButtons: View {
    let show100: Bool
    
    var buttonOptions: [Int] {
        show100 ? [25, 50, 75, 100] : [25, 50, 75]
    }
    
    @State private var selectedPercentage: Int? = nil
    
    @Binding var showAllPercentageButtons: Bool
    
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
            self.selectedPercentage = option
            onTap(option)
        }) {
            getPercentageCell(for: "\(option)", isSelected: self.selectedPercentage == option && !self.showAllPercentageButtons)
        }
        .disabled(self.selectedPercentage == option && !self.showAllPercentageButtons)
    }
    
    private func getPercentageCell(for text: String, isSelected: Bool) -> some View {
        Text(text + "%")
            .font(Theme.fonts.caption12)
            .foregroundColor(isSelected ? Color.white : .neutral0)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.blue800 : Color.blue600)
            .cornerRadius(32)
    }
}
