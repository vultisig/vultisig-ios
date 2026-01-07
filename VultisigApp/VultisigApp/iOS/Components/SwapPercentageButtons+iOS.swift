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
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
    }
    
    var buttons: some View {
        HStack{
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
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.colors.bgPrimary : Theme.colors.bgSurface1)
            .cornerRadius(16)
    }
}
#endif
