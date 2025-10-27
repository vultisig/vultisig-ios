//
//  SwapPercentageButtons+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-25.
//

#if os(iOS)
import SwiftUI

extension SwapPercentageButtons {
    var container: some View {
        buttons
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
    
    var buttons: some View {
        HStack(spacing: 6) {
            ForEach(buttonOptions, id: \.self) { option in
                getPercentageButton(for: option)
            }
        }
    }
    
    func getPercentageButton(for option: Int) -> some View {
        Button(action: {
            self.selectedPercentage = option
            onTap(option)
        }) {
            getPercentageCell(for: "\(option)", isSelected: self.selectedPercentage == option && !self.showAllPercentageButtons)
        }
        .disabled(self.selectedPercentage == option && !self.showAllPercentageButtons)
    }
    
    func getPercentageCell(for text: String, isSelected: Bool) -> some View {
        Text(text + "%")
            .font(Theme.fonts.caption12)
            .foregroundColor(isSelected ? Color.white : Theme.colors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: 60)
            .background(isSelected ? Theme.colors.bgPrimary : Theme.colors.bgSecondary)
            .cornerRadius(20)
    }
}
#endif
