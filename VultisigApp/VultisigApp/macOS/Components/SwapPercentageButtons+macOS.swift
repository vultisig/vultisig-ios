//
//  SwapPercentageButtons+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-25.
//

#if os(macOS)
import SwiftUI

extension SwapPercentageButtons {
    var container: some View {
        VStack(spacing: 8) {
            buttons
            separator
        }
        .frame(maxWidth: .infinity)
    }
    
    var separator: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundColor(Theme.colors.bgSurface2)
    }
    
    var buttons: some View {
        HStack(spacing: 8) {
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
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Theme.colors.bgPrimary : Theme.colors.bgSurface1)
            .cornerRadius(32)
    }
}
#endif
